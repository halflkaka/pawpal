import Foundation
import Supabase

/// Service layer for the `playdates` table (migration 023). Flagship
/// pet-to-pet primitive: proposer invites invitee at a time + place,
/// invitee accepts / declines, either side can cancel, and a local
/// scheduler (see `LocalNotificationsService.schedulePlaydateReminders`)
/// owns the T-24h / T-1h / T+2h reminder cadence.
///
/// Shape matches `PetsService.shared` / `ChatService.shared`:
///   * `@MainActor final class ... ObservableObject`
///   * `static let shared` singleton — a single cache is shared across
///     `FeedView`'s pinned cards, `PlaydateDetailView`, `MainTabView`'s
///     reminder re-derivation, etc. Every mutating method posts
///     `.playdateDidChange` so observers can re-derive without having
///     to know which service performed the write.
///   * `print("[Playdate] …")` logging style, matching `[LocalNotif]`
///     / `[Push]` / `[ChatService]`.
///
/// Optimistic writes: every state-transition method (`accept`,
/// `decline`, `cancel`, `markCompleted`) patches the local cache before
/// the Supabase round-trip and rolls back on failure, matching
/// `ChatService.sendMessage`. `propose` doesn't have a local "before"
/// state so it skips the rollback path — on failure the cache is
/// simply untouched and `errorMessage` is set.
@MainActor
final class PlaydateService: ObservableObject {
    /// Shared singleton — see header comment.
    static let shared = PlaydateService()

    /// Cached rows keyed by playdate id. `FeedView` derives both the
    /// request-card list (proposed invitee rows) and countdown-card
    /// list (accepted, next-48h) from this dict on every
    /// `.playdateDidChange`.
    @Published private(set) var playdates: [UUID: RemotePlaydate] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: SupabaseClient

    private init() {
        client = SupabaseConfig.client
    }

    // MARK: - Reads

    /// Loads every playdate relevant to `userID` — both sides of the
    /// row, every status — and replaces the cache. `FeedView` calls
    /// this on first appear + user change; `MainTabView` re-derives
    /// reminders after.
    ///
    /// Posts `.playdateDidChange` with `object = nil` on completion
    /// (success or error) so observers re-derive once the load
    /// settles.
    func loadUpcoming(for userID: UUID) async {
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            NotificationCenter.default.post(
                name: .playdateDidChange,
                object: nil
            )
        }

        do {
            let rows: [RemotePlaydate] = try await client
                .from("playdates")
                .select("*")
                .or("proposer_user_id.eq.\(userID.uuidString),invitee_user_id.eq.\(userID.uuidString)")
                .order("scheduled_at", ascending: true)
                .execute()
                .value
            var byID: [UUID: RemotePlaydate] = [:]
            for row in rows { byID[row.id] = row }
            playdates = byID
        } catch {
            print("[Playdate] loadUpcoming 失败: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    /// Fetches every playdate (any status) relevant to the currently
    /// authenticated user — both proposer-side and invitee-side — in a
    /// single OR query, dedupes defensively by id, and returns them
    /// sorted by `scheduled_at` ascending (soonest first, falling back
    /// to `created_at` desc for rows that share the same scheduled_at).
    ///
    /// Used by `PlaydatesListView` ("我的约玩") which needs the full
    /// history across all the user's pets, not just the next-48h cards
    /// `FeedView` derives. Also updates the shared cache so detail
    /// pushes from the list render instantly without re-fetching.
    ///
    /// Throws on failure so the list view can distinguish a real error
    /// (show retry) from an empty history (show empty state). Matches
    /// the throwing shape requested by the consumer — `loadUpcoming`
    /// stays non-throwing because it owns the shared cache load path.
    func fetchAllForCurrentUser() async throws -> [RemotePlaydate] {
        guard let userID = await currentUserID() else {
            // Not signed in — nothing to show. Return empty rather than
            // throwing, so the list view renders its (rare) empty state
            // instead of a "load failed" banner.
            return []
        }

        let rows: [RemotePlaydate] = try await client
            .from("playdates")
            .select("*")
            .or("proposer_user_id.eq.\(userID.uuidString),invitee_user_id.eq.\(userID.uuidString)")
            .order("scheduled_at", ascending: true)
            .execute()
            .value

        // Dedupe by id — shouldn't happen (the OR branches can't match
        // the same row twice), but defensive for when someone later
        // tweaks the query to include a join.
        var byID: [UUID: RemotePlaydate] = [:]
        for row in rows { byID[row.id] = row }
        let deduped = Array(byID.values)

        // Sort: soonest scheduled_at first, then created_at desc to
        // break ties on the same-day case.
        let sorted = deduped.sorted { lhs, rhs in
            if lhs.scheduled_at != rhs.scheduled_at {
                return lhs.scheduled_at < rhs.scheduled_at
            }
            return lhs.created_at > rhs.created_at
        }

        // Warm the shared cache so a tap into `PlaydateDetailView` from
        // the list renders against the same row the detail view's
        // optimistic writes patch into.
        for row in sorted { playdates[row.id] = row }

        return sorted
    }

    /// Fetches one playdate by id with both pets embedded via PostgREST.
    /// Used by `DeepLinkPlaydateLoader` when the cache doesn't already
    /// carry the row (e.g. a push tap from a cold start).
    ///
    /// On success the row is also written into the cache so subsequent
    /// reads are instant. Joined pet rows are discarded here — the
    /// detail view looks pets up via `PetsService` / a dedicated fetch.
    func fetch(id: UUID) async -> RemotePlaydate? {
        do {
            // Embed string carries both the legacy (proposer_pet /
            // invitee_pet) fast-path joins and the new
            // playdate_participants junction with its own pets +
            // profiles embeds — the detail view can render either
            // the 2-avatar 1:1 header or the N-avatar group header
            // off this single fetch.
            let row: RemotePlaydate = try await client
                .from("playdates")
                .select("*, proposer_pet:pets!proposer_pet_id(*), invitee_pet:pets!invitee_pet_id(*), playdate_participants(*, pets(*), profiles(*))")
                .eq("id", value: id.uuidString)
                .single()
                .execute()
                .value
            playdates[row.id] = row
            return row
        } catch {
            print("[Playdate] fetch(id:) 失败: \(error)")
            return nil
        }
    }

    // MARK: - Writes

    /// Backward-compat single-invitee overload for the 1:1 code paths
    /// that pre-date migration 028's group-playdate work. Internally
    /// wraps the invitee into a one-element `PetRef` array and
    /// forwards to the multi-invitee `propose(...)` below.
    ///
    /// Keeping the old signature means the `PlaydateComposerSheet`
    /// single-pet flow, any deep-link-driven composer, and existing
    /// tests keep working unchanged — the behavioural shift (junction
    /// rows get inserted too) is contained inside `propose` /
    /// `proposeSeries`.
    func propose(
        proposerPetID: UUID,
        inviteePetID: UUID,
        inviteeUserID: UUID,
        scheduledAt: Date,
        locationName: String,
        coord: (lat: Double, lng: Double)?,
        message: String?,
        repeatWeekly: Bool = false
    ) async -> RemotePlaydate? {
        await propose(
            proposerPetID: proposerPetID,
            inviteePets: [PetRef(petID: inviteePetID, ownerUserID: inviteeUserID)],
            scheduledAt: scheduledAt,
            locationName: locationName,
            coord: coord,
            message: message,
            repeatWeekly: repeatWeekly
        )
    }

    /// Inserts a new `proposed` row, then re-reads it back so the
    /// caller has the server-assigned `created_at` / `updated_at`.
    /// Returns nil (and sets `errorMessage`) on failure — including
    /// the `invitee_pet_not_open_to_playdates` trigger rejection,
    /// which surfaces as a generic Postgres error string.
    ///
    /// Posts `.playdateDidChange` with `object = row.id` on success so
    /// `MainTabView` can re-schedule reminders (no reminders fire for
    /// `proposed` status, but the observer is idempotent).
    ///
    /// For group playdates (`inviteePets.count > 1`) the proposer's
    /// junction row starts as `accepted` (they've committed by
    /// composing); invitee rows start as `proposed`. The composer UI
    /// caps `inviteePets` at 2; the schema trigger
    /// `enforce_playdate_participant_count` catches anything past
    /// 3 defensively.
    ///
    /// The legacy `proposer_pet_id` / `invitee_pet_id` columns on the
    /// parent row are populated with the proposer pet and the FIRST
    /// invitee respectively — this keeps the 1:1 UI code paths that
    /// read these columns directly working without modification.
    func propose(
        proposerPetID: UUID,
        inviteePets: [PetRef],
        scheduledAt: Date,
        locationName: String,
        coord: (lat: Double, lng: Double)?,
        message: String?,
        repeatWeekly: Bool = false
    ) async -> RemotePlaydate? {
        guard let firstInvitee = inviteePets.first else {
            errorMessage = "请至少邀请一只毛孩子"
            return nil
        }
        // Defense in depth — UI caps at 2 invitees, schema trigger
        // rejects >3 participants total. Surface a readable error
        // here before we even try the round-trip.
        guard inviteePets.count <= 2 else {
            errorMessage = "一次遛弯最多邀请 2 只毛孩子"
            return nil
        }
        let inviteePetID = firstInvitee.petID
        let inviteeUserID = firstInvitee.ownerUserID
        errorMessage = nil

        // The proposer's own user id is required for the RLS INSERT
        // policy (`auth.uid() = proposer_user_id`) — read it from the
        // live Supabase session rather than trusting a passed-in param.
        guard let proposerUserID = await currentUserID() else {
            errorMessage = "未登录"
            return nil
        }

        // Series fan-out path (migration 027). Mint one shared
        // `series_id` client-side, then build 4 inserts spaced 7 days
        // apart starting at `scheduledAt`. We return the
        // `series_sequence == 1` row so the caller can push it into
        // detail — that's what the user expects to land on after
        // tapping 发送邀请.
        if repeatWeekly {
            let inserted = await proposeSeries(
                proposerPetID: proposerPetID,
                inviteePets: inviteePets,
                proposerUserID: proposerUserID,
                baseScheduledAt: scheduledAt,
                locationName: locationName,
                coord: coord,
                message: message
            )
            return inserted.first
        }

        struct Insert: Encodable {
            let proposer_pet_id: UUID
            let invitee_pet_id: UUID
            let proposer_user_id: UUID
            let invitee_user_id: UUID
            let scheduled_at: Date
            let location_name: String
            let location_lat: Double?
            let location_lng: Double?
            let message: String?
        }

        let payload = Insert(
            proposer_pet_id: proposerPetID,
            invitee_pet_id: inviteePetID,
            proposer_user_id: proposerUserID,
            invitee_user_id: inviteeUserID,
            scheduled_at: scheduledAt,
            location_name: locationName,
            location_lat: coord?.lat,
            location_lng: coord?.lng,
            message: message?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )

        do {
            // Step 1 — parent playdate row. Legacy columns are still
            // populated so 1:1-era code paths keep working unchanged.
            let inserted: RemotePlaydate = try await client
                .from("playdates")
                .insert(payload)
                .select("*")
                .single()
                .execute()
                .value

            // Step 2 — junction rows. Build proposer + N invitees,
            // proposer starts 'accepted', invitees start 'proposed'.
            // A single bulk INSERT is one round-trip, fires the
            // participant-count cap trigger per row, and fires the
            // status-sync trigger per row (which is a no-op until the
            // proposer lands since derive checks for the proposer
            // first).
            try await insertParticipants(
                playdateID: inserted.id,
                proposerPetID: proposerPetID,
                proposerUserID: proposerUserID,
                inviteePets: inviteePets
            )

            // Step 3 — re-fetch with the participants embed so the
            // cached / returned row carries the full junction
            // snapshot (otherwise the detail view's initial render
            // falls back to the legacy columns and reads as 1:1 even
            // for group playdates).
            let withParticipants = await fetch(id: inserted.id) ?? inserted
            playdates[withParticipants.id] = withParticipants

            NotificationCenter.default.post(
                name: .playdateDidChange,
                object: withParticipants.id
            )
            // Instrumentation: viral-loop signal — proposing a
            // playdate is a high-intent pet-to-pet action. Emitted
            // after the DB insert has settled.
            AnalyticsService.shared.log(.playdateProposed)
            return withParticipants
        } catch {
            print("[Playdate] propose 失败: \(error)")
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Inserts 2-3 junction rows for the given playdate — one
    /// 'proposer' row starting as 'accepted', plus one 'invitee' row
    /// per element of `inviteePets` starting as 'proposed'. Bulk
    /// insert so the count-cap trigger only sees the batch once. The
    /// migration 028 status-sync trigger fires per row, but the
    /// derive function only returns 'accepted' once every invitee is
    /// also 'accepted', so it correctly stays at 'proposed' after
    /// this call.
    private func insertParticipants(
        playdateID: UUID,
        proposerPetID: UUID,
        proposerUserID: UUID,
        inviteePets: [PetRef]
    ) async throws {
        struct ParticipantInsert: Encodable {
            let playdate_id: UUID
            let pet_id: UUID
            let user_id: UUID
            let role: String
            let status: String
        }

        var payloads: [ParticipantInsert] = []
        payloads.append(ParticipantInsert(
            playdate_id: playdateID,
            pet_id: proposerPetID,
            user_id: proposerUserID,
            role: "proposer",
            status: "accepted"
        ))
        for invitee in inviteePets {
            payloads.append(ParticipantInsert(
                playdate_id: playdateID,
                pet_id: invitee.petID,
                user_id: invitee.ownerUserID,
                role: "invitee",
                status: "proposed"
            ))
        }

        try await client
            .from("playdate_participants")
            .insert(payloads)
            .execute()
    }

    /// Inserts 4 weekly-repeat playdates linked by a shared
    /// `series_id` (migration 027). Returns the inserted rows sorted
    /// by `series_sequence` ascending (1..4) so the caller can grab
    /// `.first` for the detail-view push.
    ///
    /// On any insert failure the cache is left unchanged and an empty
    /// array is returned. We do NOT attempt a partial rollback of
    /// already-inserted rows — Postgres can't transact across separate
    /// REST calls, and doing best-effort delete would race the
    /// notification trigger. Acceptable trade-off because the failure
    /// modes we expect (RLS rejection, invitee-not-open trigger) fire
    /// on the very first insert and short-circuit the loop before any
    /// row lands.
    private func proposeSeries(
        proposerPetID: UUID,
        inviteePets: [PetRef],
        proposerUserID: UUID,
        baseScheduledAt: Date,
        locationName: String,
        coord: (lat: Double, lng: Double)?,
        message: String?
    ) async -> [RemotePlaydate] {
        guard let firstInvitee = inviteePets.first else { return [] }
        let inviteePetID = firstInvitee.petID
        let inviteeUserID = firstInvitee.ownerUserID

        struct SeriesInsert: Encodable {
            let proposer_pet_id: UUID
            let invitee_pet_id: UUID
            let proposer_user_id: UUID
            let invitee_user_id: UUID
            let scheduled_at: Date
            let location_name: String
            let location_lat: Double?
            let location_lng: Double?
            let message: String?
            let series_id: UUID
            let series_sequence: Int
        }

        let seriesID = UUID()
        let trimmedMessage = message?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let week: TimeInterval = 7 * 24 * 60 * 60

        var payloads: [SeriesInsert] = []
        for i in 0..<4 {
            payloads.append(SeriesInsert(
                proposer_pet_id: proposerPetID,
                invitee_pet_id: inviteePetID,
                proposer_user_id: proposerUserID,
                invitee_user_id: inviteeUserID,
                scheduled_at: baseScheduledAt.addingTimeInterval(week * Double(i)),
                location_name: locationName,
                location_lat: coord?.lat,
                location_lng: coord?.lng,
                message: trimmedMessage,
                series_id: seriesID,
                series_sequence: i + 1
            ))
        }

        do {
            // Single INSERT with a 4-row payload — PostgREST returns
            // all inserted rows in one round-trip and the BEFORE
            // INSERT trigger fires per-row, so the open-to-playdates
            // gate still runs against each invitation.
            let inserted: [RemotePlaydate] = try await client
                .from("playdates")
                .insert(payloads)
                .select("*")
                .execute()
                .value
            let sorted = inserted.sorted {
                ($0.series_sequence ?? 0) < ($1.series_sequence ?? 0)
            }

            // Insert junction rows per series instance. Each instance
            // gets its own 2-3 participant rows; sharing rows across
            // instances would break per-instance accept/decline.
            // Sequential rather than a single bulk payload — the
            // count-cap trigger is per-playdate, so batching across
            // playdates would trip false positives.
            for row in sorted {
                try await insertParticipants(
                    playdateID: row.id,
                    proposerPetID: proposerPetID,
                    proposerUserID: proposerUserID,
                    inviteePets: inviteePets
                )
            }

            // Warm the cache with the post-junction fetch so the
            // detail view sees the full participant list on first
            // render.
            var refreshed: [RemotePlaydate] = []
            for row in sorted {
                if let withParticipants = await fetch(id: row.id) {
                    refreshed.append(withParticipants)
                } else {
                    refreshed.append(row)
                    playdates[row.id] = row
                }
            }

            NotificationCenter.default.post(
                name: .playdateDidChange,
                object: refreshed.first?.id
            )
            // Instrumentation: count the *series* as one viral-loop
            // signal rather than four — the user performed one
            // high-intent action. Matches how we'd want to read this
            // in the funnel.
            AnalyticsService.shared.log(.playdateProposed)
            return refreshed
        } catch {
            print("[Playdate] proposeSeries 失败: \(error)")
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// Cancels every future, non-finalised playdate in the given
    /// series (migration 027). Past instances and rows already in
    /// `declined` / `cancelled` / `completed` are left alone.
    ///
    /// Filter chain mirrors the RLS policy as defence in depth — RLS
    /// already gates participant-only writes, but the explicit
    /// `proposer_user_id == me OR invitee_user_id == me` predicate
    /// keeps the intent visible at the call site (and is harmless if
    /// RLS ever loosens).
    @discardableResult
    func cancelSeries(seriesID: UUID) async -> Bool {
        errorMessage = nil

        guard let userID = await currentUserID() else {
            errorMessage = "未登录"
            return false
        }

        struct StatusUpdate: Encodable {
            let status: String
        }

        // Optimistic — flip every cache row that matches the same
        // predicate so UI listening to `.playdateDidChange` reflects
        // the cancel immediately. Rollback on failure mirrors the
        // single-row `transitionStatus` helper.
        let nowSnapshot = Date()
        let previous = playdates
        for (id, row) in playdates {
            guard row.series_id == seriesID,
                  row.scheduled_at > nowSnapshot,
                  row.status == .proposed || row.status == .accepted,
                  row.proposer_user_id == userID || row.invitee_user_id == userID
            else { continue }
            var optimistic = row
            optimistic.status = .cancelled
            playdates[id] = optimistic
        }

        do {
            try await client
                .from("playdates")
                .update(StatusUpdate(status: RemotePlaydate.Status.cancelled.rawValue))
                .eq("series_id", value: seriesID.uuidString)
                .in("status", values: [
                    RemotePlaydate.Status.proposed.rawValue,
                    RemotePlaydate.Status.accepted.rawValue
                ])
                .gt("scheduled_at", value: ISO8601DateFormatter().string(from: nowSnapshot))
                .or("proposer_user_id.eq.\(userID.uuidString),invitee_user_id.eq.\(userID.uuidString)")
                .execute()
            NotificationCenter.default.post(
                name: .playdateDidChange,
                object: nil
            )
            return true
        } catch {
            print("[Playdate] cancelSeries 失败: \(error)")
            // Rollback the optimistic cache flips.
            playdates = previous
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Transitions a `proposed` row to `accepted`. Optimistic — on
    /// failure the cache is reverted to the prior status and
    /// `errorMessage` is set.
    @discardableResult
    func accept(_ id: UUID) async -> Bool {
        let ok = await transitionStatus(id: id, to: .accepted, logLabel: "accept")
        // Instrumentation: viral-loop signal — accepting closes the
        // pet-to-pet handshake. Emitted only on the success path; a
        // failed transition is already logged by the helper.
        if ok {
            AnalyticsService.shared.log(.playdateAccepted)
        }
        return ok
    }

    /// Transitions a `proposed` row to `declined`. Optimistic.
    @discardableResult
    func decline(_ id: UUID) async -> Bool {
        await transitionStatus(id: id, to: .declined, logLabel: "decline")
    }

    /// Transitions a row to `cancelled` from any non-terminal state.
    /// Either side can call this.
    @discardableResult
    func cancel(_ id: UUID) async -> Bool {
        await transitionStatus(id: id, to: .cancelled, logLabel: "cancel")
    }

    /// Transitions an `accepted` row to `completed`. Currently unused
    /// in MVP (the `FeedView` post-playdate prompt runs off the
    /// `scheduled_at + 2h` time window regardless of status, per
    /// §9.5 of the spec) — included for parity with the spec surface
    /// and for the deferred sweeper.
    @discardableResult
    func markCompleted(_ id: UUID) async -> Bool {
        await transitionStatus(id: id, to: .completed, logLabel: "markCompleted")
    }

    // MARK: - Per-participant RPCs (migration 028)

    /// Invitee flips their own junction row to 'accepted'. Migration
    /// 028's `sync_playdate_status_from_participants` trigger
    /// re-derives the top-level `playdates.status`; this method
    /// re-fetches the parent row afterwards so the cache (and every
    /// observer of `.playdateDidChange`) sees the post-trigger state.
    ///
    /// `petID` must be a pet owned by the caller — the RPC's
    /// `pet_not_owned_by_caller` check will reject otherwise.
    @discardableResult
    func acceptInvitation(playdateID: UUID, petID: UUID) async -> Bool {
        errorMessage = nil
        struct Params: Encodable {
            let pd_id: UUID
            let my_pet_id: UUID
        }
        do {
            try await client
                .rpc("accept_playdate_participant",
                     params: Params(pd_id: playdateID, my_pet_id: petID))
                .execute()
            // Trigger derived the new top-level status — re-fetch so
            // the cache reflects it (and the participant embed updates
            // too). `fetch(id:)` writes into `playdates` for us.
            _ = await fetch(id: playdateID)
            NotificationCenter.default.post(
                name: .playdateDidChange,
                object: playdateID
            )
            AnalyticsService.shared.log(.playdateAccepted)
            return true
        } catch {
            print("[Playdate] acceptInvitation 失败: \(error)")
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Invitee flips their own junction row to 'declined'. Even one
    /// dissent breaks the group — the derive trigger collapses the
    /// top-level status to 'declined'.
    @discardableResult
    func declineInvitation(playdateID: UUID, petID: UUID) async -> Bool {
        errorMessage = nil
        struct Params: Encodable {
            let pd_id: UUID
            let my_pet_id: UUID
        }
        do {
            try await client
                .rpc("decline_playdate_participant",
                     params: Params(pd_id: playdateID, my_pet_id: petID))
                .execute()
            _ = await fetch(id: playdateID)
            NotificationCenter.default.post(
                name: .playdateDidChange,
                object: playdateID
            )
            return true
        } catch {
            print("[Playdate] declineInvitation 失败: \(error)")
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Proposer cancels the entire playdate. Flips every junction row
    /// to 'cancelled' and the parent row to 'cancelled' in one RPC
    /// call. Only the proposer can invoke this — invitees wanting out
    /// should call `declineInvitation` instead.
    @discardableResult
    func cancelAsProposer(playdateID: UUID) async -> Bool {
        errorMessage = nil
        struct Params: Encodable {
            let pd_id: UUID
        }
        do {
            try await client
                .rpc("cancel_playdate_as_proposer",
                     params: Params(pd_id: playdateID))
                .execute()
            _ = await fetch(id: playdateID)
            NotificationCenter.default.post(
                name: .playdateDidChange,
                object: playdateID
            )
            return true
        } catch {
            print("[Playdate] cancelAsProposer 失败: \(error)")
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Internals

    /// Shared status-transition helper. Optimistic cache update +
    /// rollback on failure + `.playdateDidChange` post on success.
    private func transitionStatus(
        id: UUID,
        to newStatus: RemotePlaydate.Status,
        logLabel: String
    ) async -> Bool {
        guard let previous = playdates[id] else {
            print("[Playdate] \(logLabel) 失败: 未在缓存中找到 \(id)")
            errorMessage = "找不到这次遛弯"
            return false
        }

        // Optimistic — flip the cache immediately so the UI refreshes
        // on the same RunLoop tick. Rollback below on DB failure.
        var optimistic = previous
        optimistic.status = newStatus
        playdates[id] = optimistic

        struct StatusUpdate: Encodable {
            let status: String
        }

        do {
            try await client
                .from("playdates")
                .update(StatusUpdate(status: newStatus.rawValue))
                .eq("id", value: id.uuidString)
                .execute()
            NotificationCenter.default.post(
                name: .playdateDidChange,
                object: id
            )
            return true
        } catch {
            print("[Playdate] \(logLabel) 失败: \(error)")
            // Rollback — the UI snaps back to the previous status.
            playdates[id] = previous
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Reads the authenticated user's id from the shared Supabase
    /// client's session. Returns nil when signed out — `propose`
    /// short-circuits in that case since the RLS insert policy would
    /// reject anyway.
    private func currentUserID() async -> UUID? {
        do {
            let session = try await client.auth.session
            return session.user.id
        } catch {
            print("[Playdate] currentUserID 失败: \(error)")
            return nil
        }
    }
}

// MARK: - PetRef
//
// Small value type bundling a pet id with its owner's user id — the
// minimum needed to populate a junction row, plus the legacy
// `invitee_user_id` column on the parent playdate row. Passing a
// dedicated struct (rather than a tuple) keeps the service API
// readable at call sites: `inviteePets: [PetRef]` is self-documenting
// in a way that `[(UUID, UUID)]` isn't.
struct PetRef: Hashable, Sendable {
    let petID: UUID
    let ownerUserID: UUID

    init(petID: UUID, ownerUserID: UUID) {
        self.petID = petID
        self.ownerUserID = ownerUserID
    }

    /// Convenience so composer code that already holds a `RemotePet`
    /// can produce the ref without unpacking fields at the call site.
    init(pet: RemotePet) {
        self.petID = pet.id
        self.ownerUserID = pet.owner_user_id
    }
}

// MARK: - Cross-view change broadcast
//
// Every mutating method posts this notification with the affected
// playdate id as `object` (nil for bulk loads). `MainTabView` listens
// and re-derives `LocalNotificationsService.schedulePlaydateReminders`
// from the updated cache; `FeedView` uses it to recompute pinned
// request / countdown cards without a pull-to-refresh.
extension Notification.Name {
    static let playdateDidChange = Notification.Name("PawPal.playdateDidChange")
}

// Tiny internal sugar used by `propose` above — mirrors the extension
// inside `ChatService.swift`. Local to this file to avoid a duplicate
// top-level declaration conflict.
private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
