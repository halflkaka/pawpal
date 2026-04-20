import Foundation
import Supabase

/// Shared, in-app store for the virtual pet's session + persisted state.
///
/// Why a store instead of two `@State` variables per view: the virtual pet
/// is rendered in *two* places — `ProfileView` (owner's own card) and
/// `PetProfileView` (any pet opened from the feed / search). Previously
/// each site owned its own `@State` for tap count + bar values, so the
/// two screens drifted apart:
///
/// * "已经摸了kaka X 下" was reset every time you switched screens because
///   `VirtualPetView`'s internal `@State var tapCount = 0` was re-initialised
///   when the view tree was rebuilt (CHANGELOG #45).
/// * 喂食 / 玩耍 / 摸摸 taps bumped the bars only in the tapped view
///   because the buttons mutated local `@State`. The sibling view never
///   saw the change.
///
/// This store fixes both by centralising:
///
///   * `tapCounts`  — in-memory, session-scoped counter keyed by pet id.
///     Both views read from the same dict so "how many times has this
///     user booped kaka this session" reads the same number regardless
///     of which screen happens to be on top. Not persisted — we don't
///     want the tap counter to grow across launches (a fresh session
///     should feel fresh).
///
///   * `petStates`  — cached `PetStateSnapshot` values loaded from the
///     `pet_state` table (migration 015). These are the *persisted*
///     mood / hunger / energy values that survive relaunches. When a row
///     exists, both profile screens prefer its values over the purely
///     time-derived baseline so tapping 喂食 actually moves the bar and
///     stays moved across navigation + restart.
///
/// Both are `@Published` so SwiftUI views that observe the shared instance
/// re-render automatically whenever either changes.
@MainActor
final class VirtualPetStateStore: ObservableObject {
    /// Process-wide singleton. Views pull this via `@ObservedObject` and
    /// mutate through the provided methods — never assign the dict fields
    /// directly, because several callers need to coalesce around the same
    /// pet id.
    static let shared = VirtualPetStateStore()

    // MARK: - Published state

    /// Session-scoped tap counter keyed by pet id. Bumped on every boop
    /// (tap-to-pet) across both profile screens.
    @Published var tapCounts: [UUID: Int] = [:]

    /// Cached persisted virtual-pet stats per pet. Populated lazily: the
    /// first screen that renders a given pet triggers a fetch; any later
    /// render reuses the cached snapshot. Mutations from feed/pet/play
    /// actions update this dict *optimistically* before the server round
    /// trip so every VirtualPetView bound to the same pet re-renders
    /// immediately.
    @Published var petStates: [UUID: PetStateSnapshot] = [:]

    private let client: SupabaseClient
    /// Pet ids whose initial fetch is in flight — used to coalesce
    /// concurrent loadIfNeeded calls from two views showing the same pet.
    private var pendingFetches: Set<UUID> = []

    init() {
        client = SupabaseConfig.client
    }

    // MARK: - Tap count

    /// Current tap count for a pet. Defaults to 0 when we haven't seen
    /// any taps this session.
    func tapCount(for petID: UUID) -> Int {
        tapCounts[petID] ?? 0
    }

    /// Increment the tap counter by one. Called by `VirtualPetView.tapPet`.
    func incrementTapCount(petID: UUID) {
        tapCounts[petID, default: 0] += 1
    }

    // MARK: - Persisted pet_state

    /// Returns the cached snapshot for a pet if we already fetched it,
    /// or nil if no row was found on the server (both profile screens
    /// treat nil as "fall back to the time-derived baseline").
    ///
    /// The returned snapshot has **time-based decay already applied** —
    /// the bars drift while the owner isn't tapping so that re-opening
    /// the profile hours later shows a hungrier, calmer pet. The
    /// persisted snapshot on disk is unchanged; only the in-memory view
    /// that callers render reflects the drift. See `decayedState` for
    /// the rate constants.
    func state(for petID: UUID) -> PetStateSnapshot? {
        guard let raw = petStates[petID] else { return nil }
        return Self.decayedState(raw)
    }

    /// Ensures we have an up-to-date `pet_state` row cached for `petID`.
    /// No-ops if we're already fetching (so two views appearing at once
    /// don't fire two requests) or if the cache already has a snapshot
    /// newer than `maxAge` seconds. The default 30s is enough to survive
    /// a normal tab switch without triggering a reload.
    func loadIfNeeded(petID: UUID, maxAge: TimeInterval = 30) async {
        if pendingFetches.contains(petID) { return }
        if let existing = petStates[petID], Date().timeIntervalSince(existing.fetchedAt) < maxAge {
            return
        }
        pendingFetches.insert(petID)
        defer { pendingFetches.remove(petID) }

        do {
            // Use a list-select instead of `.single()` because a pet with
            // no owner-initiated actions yet has no row — `.single()`
            // would throw PGRST116.  An empty array just means "no
            // persisted state, use the time-derived baseline".
            let rows: [PetStateRow] = try await client
                .from("pet_state")
                .select()
                .eq("pet_id", value: petID.uuidString)
                .limit(1)
                .execute()
                .value
            if let row = rows.first {
                petStates[petID] = PetStateSnapshot(
                    mood: row.mood,
                    hunger: row.hunger,
                    energy: row.energy,
                    updatedAt: row.updated_at,
                    fetchedAt: Date()
                )
            } else {
                // Mark the fetch as complete (sentinel with nil-equivalent)
                // by explicitly removing any stale entry — the callers
                // interpret a missing key as "fall back to derived".
                petStates.removeValue(forKey: petID)
            }
        } catch {
            print("[VirtualPetStateStore] loadIfNeeded 失败 for \(petID): \(error)")
        }
    }

    /// Which owner-initiated action was tapped. Each bumps a different
    /// bar with the deltas calibrated to feel like a single interaction
    /// has a visible effect on the 0-100 scale — tapping 喂食 once moves
    /// the hunger bar from 40 → 55, not 40 → 41.
    enum PetAction {
        case feed
        case play
        case pat

        /// (mood, hunger, energy) delta applied on a single tap.
        var delta: (mood: Int, hunger: Int, energy: Int) {
            switch self {
            case .feed: return (mood:  2, hunger: 15, energy:  4)
            case .play: return (mood:  6, hunger: -4, energy: -8)
            case .pat:  return (mood:  4, hunger:  0, energy:  0)
            }
        }
    }

    /// Applies an action to `petID`'s persisted stats. Optimistic: the
    /// local cache is updated *before* the server call so the UI reflects
    /// the tap on the same animation frame. On failure we log but don't
    /// rollback — the buttons are cosmetic-leaning, and flashing the bar
    /// back to its previous value would feel worse than a stat that
    /// eventually corrects itself via `loadIfNeeded`.
    ///
    /// The `baseline` argument is the time-derived `(mood, hunger, energy)`
    /// tuple that `RemotePet+VirtualPet` computes. We use it only when we
    /// don't already have a server row for this pet — the very first tap
    /// needs *something* to start from, and the baseline is the same
    /// number the bars currently display, so the transition reads smooth.
    func applyAction(
        _ action: PetAction,
        petID: UUID,
        baseline: (mood: Int, hunger: Int, energy: Int)
    ) async {
        let delta = action.delta

        // Start from the *decayed* cached value if we have one — that
        // way an owner tapping 喂食 after a long break sees "pet was
        // hungry, just fed → bar moves up from its low point" rather
        // than "bar moves up from whatever it was 8h ago", which would
        // feel disconnected from what the bars are currently showing.
        // If we have no persisted row, fall back to the time-derived
        // baseline the UI renders.
        let start: (Int, Int, Int)
        if let cached = petStates[petID] {
            let decayed = Self.decayedState(cached)
            start = (decayed.mood, decayed.hunger, decayed.energy)
        } else {
            start = baseline
        }
        let next = PetStateSnapshot(
            mood:   clamp(start.0 + delta.mood),
            hunger: clamp(start.1 + delta.hunger),
            energy: clamp(start.2 + delta.energy),
            updatedAt: Date(),
            fetchedAt: Date()
        )

        // Optimistic local update — both views observing this store
        // re-render on the same RunLoop tick.
        petStates[petID] = next

        // Upsert so the first tap creates the row and subsequent taps
        // overwrite it. Migration 015's `pet_state` table is keyed by
        // `pet_id` so the conflict target is a single column.
        struct PetStateUpsert: Encodable {
            let pet_id: UUID
            let mood: Int
            let hunger: Int
            let energy: Int
            let updated_at: Date
        }
        let payload = PetStateUpsert(
            pet_id: petID,
            mood: next.mood,
            hunger: next.hunger,
            energy: next.energy,
            updated_at: next.updatedAt
        )

        do {
            try await client
                .from("pet_state")
                .upsert(payload, onConflict: "pet_id")
                .execute()
        } catch {
            print("[VirtualPetStateStore] applyAction 失败 (\(action)) for \(petID): \(error)")
        }
    }

    // MARK: - Time-based decay

    // Tunable: 饱食 (hunger) drops by this many points per hour since
    // the last persisted `updated_at`. Calibrated so a pet left alone
    // overnight reads visibly hungry (~9h × 3 = 27 points down) but
    // not dead — the owner should feel a nudge, not guilt.
    private static let hungerDecayPerHour: Double = -3.0

    // Tunable: 活力 (energy) recovers while the pet rests. A capped
    // positive rate keeps it from pinning at 100 instantly after play;
    // the DB CHECK constraint (0..100) plus our clamp handle the upper
    // bound.
    private static let energyRecoveryPerHour: Double = 2.0

    // Tunable: 心情 (mood) drifts downward slowly. Smaller magnitude
    // than hunger because mood is meant to be "sticky" — one great
    // play session should keep the bar high across a few hours of
    // neglect.
    private static let moodDecayPerHour: Double = -1.0

    /// Applies time-based decay to a persisted snapshot and returns a
    /// fresh one carrying the drifted values. The `updatedAt` on the
    /// returned snapshot intentionally stays pointing at the persisted
    /// server time — that's our origin for the next decay calculation
    /// and only moves forward when the owner actually taps an action.
    ///
    /// Decay rates (per hour, see tunable constants above):
    ///   * 饱食 (hunger):  -3
    ///   * 活力 (energy):  +2  (capped at 100)
    ///   * 心情 (mood):    -1
    ///
    /// The persisted row on Supabase is **never** mutated by this
    /// function — it's a pure read-side transform that the UI applies
    /// every time it reads the snapshot. `applyAction` is responsible
    /// for persisting the "tap delta on top of decayed baseline" value
    /// when the owner interacts.
    static func decayedState(
        _ snapshot: PetStateSnapshot,
        at now: Date = Date()
    ) -> PetStateSnapshot {
        // Guard against clock skew — if `updatedAt` ever ends up in
        // the future (device time reset, test fixture, etc.) treat the
        // elapsed window as zero so we don't apply reverse decay.
        let elapsed = max(0, now.timeIntervalSince(snapshot.updatedAt))
        let hours = elapsed / 3600.0

        let moodDrift   = Int((moodDecayPerHour * hours).rounded())
        let hungerDrift = Int((hungerDecayPerHour * hours).rounded())
        let energyDrift = Int((energyRecoveryPerHour * hours).rounded())

        func clampStatic(_ value: Int) -> Int { min(100, max(0, value)) }

        var next = snapshot
        next.mood   = clampStatic(snapshot.mood   + moodDrift)
        next.hunger = clampStatic(snapshot.hunger + hungerDrift)
        next.energy = clampStatic(snapshot.energy + energyDrift)
        // Leave updatedAt alone — it's the origin of the decay window
        // and must only advance when we genuinely persist a new value.
        return next
    }

    // MARK: - Helpers

    /// Keep every stat bar inside the 0-100 range the DB CHECK constraints
    /// enforce. A buggy delta table or unexpected starting value can't
    /// leave us with an out-of-range integer that the renderer can't map.
    private func clamp(_ value: Int) -> Int {
        min(100, max(0, value))
    }

    /// Raw row shape from the `pet_state` table. Mirrors migration 015.
    private struct PetStateRow: Decodable {
        let pet_id: UUID
        let mood: Int
        let hunger: Int
        let energy: Int
        let updated_at: Date
    }
}

/// Client-side view of a `pet_state` row. Decoupled from the DB row
/// struct (which is private to the store) so callers get a stable shape
/// even if we rename columns later.
struct PetStateSnapshot: Equatable {
    var mood: Int
    var hunger: Int
    var energy: Int
    /// Server-side `updated_at`. Kept around so callers can show "last
    /// fed 5m ago" style hints if we ever want to expose freshness.
    var updatedAt: Date
    /// When this snapshot was fetched locally. Used by `loadIfNeeded`
    /// to decide whether the cache is stale.
    var fetchedAt: Date
}
