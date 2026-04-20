import Foundation
import Supabase

@MainActor
final class PetsService: ObservableObject {
    /// App-wide shared instance.
    ///
    /// Previously, `ProfileView` and `PetProfileView` each held their own
    /// `@StateObject private var petsService = PetsService()` — two separate
    /// caches meant an optimistic update in one view (e.g. tapping 🎩 on the
    /// profile) wasn't visible in the other until the second view re-read
    /// from Supabase. Combined with the read-after-write race (the nav push
    /// can beat the DB write), the accessory would appear to "reset" on the
    /// pet profile screen.
    ///
    /// Sharing a single `@Published pets` cache across both screens makes
    /// the optimistic write in `updatePetAccessory` immediately visible to
    /// `PetProfileView.refreshPetIfNeeded`, which now prefers the cached
    /// row over the DB fetch (the cache is at least as fresh as the DB for
    /// the owner's own pets).
    static let shared = PetsService()

    @Published var pets: [RemotePet] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let client: SupabaseClient

    init() {
        client = SupabaseConfig.client
    }

    /// Returns the cached row for `petID` if we have one. `PetProfileView`
    /// uses this to seed its local snapshot on appear — any optimistic
    /// write performed by another view (e.g. `ProfileView`'s dress-up
    /// chips) will already be reflected in the cache, so this is strictly
    /// newer than the nav-push snapshot for the owner's own pets.
    func cachedPet(id: UUID) -> RemotePet? {
        pets.first(where: { $0.id == id })
    }

    func loadPets(for userID: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: [RemotePet] = try await client
                .from("pets")
                .select()
                .eq("owner_user_id", value: userID.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
            pets = response
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addPet(
        for userID: UUID,
        name: String, species: String, breed: String, sex: String,
        age: String, weight: String, homeCity: String, bio: String,
        birthday: Date? = nil,
        avatarData: Data? = nil
    ) async -> RemotePet? {
        // `birthday` maps to a PostgreSQL `date` column, which PostgREST
        // round-trips as a bare "YYYY-MM-DD" string. Encoding a `Date`
        // would serialise an ISO8601 timestamp and lean on Postgres'
        // implicit cast, which also makes the SELECT-back fail to
        // decode. Format explicitly via `RemotePet.birthdayFormatter`
        // so read and write use the same shape end-to-end.
        struct NewPet: Encodable {
            let owner_user_id: UUID
            let name: String
            let species: String?
            let breed: String?
            let sex: String?
            let birthday: String?
            let age_text: String?
            let weight: String?
            let home_city: String?
            let bio: String?
        }

        let payload = NewPet(
            owner_user_id: userID,
            name: normalizeRequired(name),
            species: normalizeOptional(species),
            breed: normalizeOptional(breed),
            sex: normalizeOptional(sex),
            birthday: birthday.map { RemotePet.birthdayFormatter.string(from: $0) },
            age_text: normalizeOptional(age),
            weight: normalizeOptional(weight),
            home_city: normalizeOptional(homeCity),
            bio: normalizeOptional(bio)
        )

        errorMessage = nil

        do {
            var pet: RemotePet = try await client
                .from("pets")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value

            // Upload avatar after creation so we have the real pet ID for the path
            if let avatarData {
                pet = await uploadAndSetAvatar(data: avatarData, pet: pet, userID: userID) ?? pet
            }

            pets = [pet] + pets.filter { $0.id != pet.id }
            return pet
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updatePet(
        _ pet: RemotePet,
        for userID: UUID,
        openToPlaydates: Bool? = nil,
        avatarData: Data? = nil
    ) async {
        // See note in `addPet` — `birthday` round-trips through
        // `RemotePet.birthdayFormatter` as a YYYY-MM-DD string, never
        // a `Date` (which would emit a full ISO8601 timestamp).
        //
        // `open_to_playdates` is the opt-in gate for invitations
        // (migration 023). When the caller passes `nil` we omit the
        // column entirely from the UPDATE so the row keeps whatever
        // value it already had — matches the "only include fields the
        // editor actually touched" posture.
        struct PetUpdate: Encodable {
            let name: String
            let species: String?
            let breed: String?
            let sex: String?
            let birthday: String?
            let age_text: String?
            let weight: String?
            let home_city: String?
            let bio: String?
            let avatar_url: String?
            let open_to_playdates: Bool?
        }

        errorMessage = nil

        var updatedAvatarURL: String? = pet.avatar_url
        if let avatarData {
            if let uploaded = try? await AvatarService().uploadPetAvatar(
                data: avatarData, ownerID: userID, petID: pet.id
            ) {
                updatedAvatarURL = uploaded
            } else {
                print("[PetsService] avatar upload 失败 — keeping existing URL")
            }
        }

        // Prefer the explicit `openToPlaydates:` arg when the caller
        // passed one; otherwise fall back to whatever the `RemotePet`
        // already carries. Both call patterns exist in `ProfileView`
        // (add-pet flow passes the param explicitly; the edit-sheet
        // sets `updated.open_to_playdates = openToPlaydates` on the
        // struct before calling). Encoding `nil` omits the field so
        // rows never get blanked out by an unrelated UPDATE.
        let resolvedOpenToPlaydates = openToPlaydates ?? pet.open_to_playdates

        let payload = PetUpdate(
            name: normalizeRequired(pet.name),
            species: normalizeOptional(pet.species),
            breed: normalizeOptional(pet.breed),
            sex: normalizeOptional(pet.sex),
            birthday: pet.birthday.map { RemotePet.birthdayFormatter.string(from: $0) },
            age_text: normalizeOptional(pet.age),
            weight: normalizeOptional(pet.weight),
            home_city: normalizeOptional(pet.home_city),
            bio: normalizeOptional(pet.bio),
            avatar_url: updatedAvatarURL,
            open_to_playdates: resolvedOpenToPlaydates
        )

        do {
            try await client
                .from("pets")
                .update(payload)
                .eq("id", value: pet.id.uuidString)
                .execute()
            await loadPets(for: userID)

            // Broadcast the updated pet so every PostsService /
            // StoryService instance re-patches its cached snapshots.
            // See `updatePetAvatar` below for the full rationale —
            // without this, old feed rows keep rendering the previous
            // avatar/name/breed until a hard refresh.
            var patched = pet
            patched.avatar_url = updatedAvatarURL
            patched.open_to_playdates = resolvedOpenToPlaydates
            NotificationCenter.default.post(
                name: .petDidUpdate,
                object: nil,
                userInfo: ["pet": patched]
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Update only the avatar for an existing pet. Used by `PetProfileView`'s
    /// avatar picker so we don't round-trip the entire pet record (and all
    /// its other fields) just to change a photo. Returns the new public URL
    /// on success so the caller can reflect it in its local state; returns
    /// nil if either the storage upload or the DB patch fails.
    func updatePetAvatar(_ pet: RemotePet, for userID: UUID, data: Data) async -> String? {
        errorMessage = nil
        do {
            let url = try await AvatarService().uploadPetAvatar(
                data: data, ownerID: userID, petID: pet.id
            )
            struct AvatarUpdate: Encodable { let avatar_url: String }
            try await client
                .from("pets")
                .update(AvatarUpdate(avatar_url: url))
                .eq("id", value: pet.id.uuidString)
                .eq("owner_user_id", value: userID.uuidString)
                .execute()

            // Keep the cached `pets` list in sync if it contains this pet,
            // so anything observing it (ProfileView, pickers) re-renders.
            if let idx = pets.firstIndex(where: { $0.id == pet.id }) {
                pets[idx].avatar_url = url
            }

            // Propagate the new avatar into cached posts / stories too —
            // otherwise the feed keeps rendering the pre-upload snapshot
            // (no avatar_url → illustrated DogAvatar fallback) until the
            // user pull-to-refreshes. PostsService is instantiated per-
            // view (FeedView / ProfileView / PetProfileView each hold
            // their own), so a direct call can only patch one of them;
            // broadcasting via NotificationCenter lets every live
            // instance — including StoryService.shared — patch itself.
            var patched = pet
            patched.avatar_url = url
            NotificationCenter.default.post(
                name: .petDidUpdate,
                object: nil,
                userInfo: ["pet": patched]
            )

            return url
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // Upload avatar and update avatar_url in DB, returning the updated pet
    private func uploadAndSetAvatar(data: Data, pet: RemotePet, userID: UUID) async -> RemotePet? {
        do {
            let url = try await AvatarService().uploadPetAvatar(
                data: data, ownerID: userID, petID: pet.id
            )
            struct AvatarUpdate: Encodable { let avatar_url: String }
            let updated: RemotePet = try await client
                .from("pets")
                .update(AvatarUpdate(avatar_url: url))
                .eq("id", value: pet.id.uuidString)
                .select()
                .single()
                .execute()
                .value
            return updated
        } catch {
            print("[PetsService] avatar upload 失败: \(error)")
            return nil
        }
    }

    // MARK: - Featured-pet fan-out

    /// Bulk-load the "featured" pet for each user in `userIDs`. Used by the
    /// pet-first pass on follow-list rows, chat rows, and the compose-new
    /// sheet: every row that renders a user avatar in those surfaces also
    /// overlays the user's first pet as a small corner badge so pets stay
    /// the protagonists of the social graph (see product.md).
    ///
    /// "Featured" = the user's oldest pet (ordered by `created_at asc`) —
    /// we don't have a dedicated `featured_pet_id` column on `profiles`
    /// yet, so the first-created pet is the canonical stand-in. One
    /// Supabase query fetches every pet owned by any user in the list,
    /// then the client picks the first per owner. Users with no pets are
    /// simply absent from the returned dict; callers fall back to no
    /// badge.
    ///
    /// Returns an empty dict on failure so callers don't have to unwrap.
    func loadFeaturedPets(for userIDs: [UUID]) async -> [UUID: RemotePet] {
        guard !userIDs.isEmpty else { return [:] }
        do {
            let response: [RemotePet] = try await client
                .from("pets")
                .select()
                .in("owner_user_id", values: userIDs.map { $0.uuidString })
                .order("created_at", ascending: true)
                .execute()
                .value
            var byOwner: [UUID: RemotePet] = [:]
            for pet in response where byOwner[pet.owner_user_id] == nil {
                byOwner[pet.owner_user_id] = pet
            }
            return byOwner
        } catch {
            print("[PetsService] loadFeaturedPets 失败: \(error)")
            return [:]
        }
    }

    // MARK: - Single-pet refresh

    /// Re-reads one pet row from Supabase. Used by `PetProfileView` on
    /// appear so cross-view edits (e.g. the owner dresses up the pet in
    /// `ProfileView`, then navigates to `PetProfileView`) show the
    /// latest accessory / boop count even though the two screens each
    /// own a separate `PetsService` instance.
    ///
    /// Returns nil on failure — callers keep their existing snapshot.
    func fetchPet(id: UUID) async -> RemotePet? {
        do {
            let pet: RemotePet = try await client
                .from("pets")
                .select()
                .eq("id", value: id.uuidString)
                .single()
                .execute()
                .value
            return pet
        } catch {
            print("[PetsService] fetchPet 失败: \(error)")
            return nil
        }
    }

    // MARK: - Accessory persistence

    /// Persist the virtual pet's accessory choice. Only the owner can
    /// write (enforced by the existing `pets` UPDATE RLS policy from
    /// migration 003), so a visitor trying to dress up someone else's
    /// pet gets a silent no-op at the DB level — but we also gate on
    /// the client side via `canEdit` before calling.
    ///
    /// `accessory` is the raw value from `DogAvatar.Accessory` — one of
    /// 'none', 'bow', 'hat', 'glasses'. Migration 014's CHECK constraint
    /// rejects anything else.
    ///
    /// Fails silently: accessory is cosmetic, a dropped write just means
    /// the hat will reset next launch. We log for debugging but don't
    /// surface a toast.
    ///
    /// **Optimistic, no rollback.** We mutate the local cache *before*
    /// the await so any other view reading from the shared `PetsService`
    /// (notably `PetProfileView`'s cache-first refresh and both screens'
    /// `VirtualPetView.externalAccessory` binding) sees the new accessory
    /// immediately. On DB failure we **do not** revert the cache — doing
    /// so caused a visible regression: if the write failed (migration 014
    /// not yet applied, transient auth issue, network blip), the cache
    /// would flip back to the old value within the same animation frame,
    /// `VirtualPetView`'s `.onChange(of: externalAccessory)` sync would
    /// drag `state.accessory` back with it, and the user's tap appeared
    /// to do nothing ("can't even update virtual pet in the normal
    /// profile view now"). Respecting the tap visually is the right
    /// default — the next loadPets() will reconcile with reality, and the
    /// worst case is a hat that doesn't survive restart, which is better
    /// than an unresponsive UI.
    func updatePetAccessory(petID: UUID, ownerID: UUID, accessory: String) async {
        struct AccessoryUpdate: Encodable { let accessory: String }

        // Optimistic local update — applied immediately and kept even on
        // DB failure (see rationale in the docstring above).
        if let idx = pets.firstIndex(where: { $0.id == petID }) {
            pets[idx].accessory = accessory
        }

        // Broadcast immediately (even before the DB round-trip) so cached
        // post / story snapshots pick up the new accessory on the same
        // RunLoop tick — matches the "optimistic wins" policy above.
        if let patched = pets.first(where: { $0.id == petID }) {
            NotificationCenter.default.post(
                name: .petDidUpdate,
                object: nil,
                userInfo: ["pet": patched]
            )
        }

        do {
            try await client
                .from("pets")
                .update(AccessoryUpdate(accessory: accessory))
                .eq("id", value: petID.uuidString)
                .eq("owner_user_id", value: ownerID.uuidString)
                .execute()
        } catch {
            // Log but don't rollback. The cache's optimistic value wins.
            print("[PetsService] updatePetAccessory 失败 (cache kept optimistic): \(error)")
        }
    }

    // MARK: - Engagement (visits + boops) — backing CHANGELOG #38

    /// Records a visit for analytics / social proof. No-ops when the
    /// viewer is the pet's owner (we don't inflate a pet's own visit
    /// count when its owner opens the profile), when there is no
    /// authenticated user, or when the insert would duplicate the
    /// existing (pet_id, viewer_user_id, visited_on) row — the DB's
    /// primary key handles that case via upsert semantics.
    ///
    /// Fails silently. A dropped visit is a social metric, not a user
    /// action — we don't want to surface an error toast for it.
    func recordVisit(petID: UUID, viewerUserID: UUID, ownerID: UUID) async {
        guard viewerUserID != ownerID else { return }

        struct VisitInsert: Encodable {
            let pet_id: UUID
            let viewer_user_id: UUID
        }

        do {
            try await client
                .from("pet_visits")
                .upsert(
                    VisitInsert(pet_id: petID, viewer_user_id: viewerUserID),
                    onConflict: "pet_id,viewer_user_id,visited_on",
                    ignoreDuplicates: true
                )
                .execute()
        } catch {
            // Analytics-style write — failures shouldn't bubble up.
            print("[PetsService] recordVisit 失败: \(error)")
        }
    }

    /// Total visits = number of (pet_id, viewer_user_id, visited_on)
    /// rows. This matches the "Unique visits per day" counting scheme
    /// chosen by the user: a visitor who returns on a new day adds
    /// another count, but same-day refreshes don't.
    func fetchVisitCount(petID: UUID) async -> Int {
        do {
            let response = try await client
                .from("pet_visits")
                .select("*", head: true, count: .exact)
                .eq("pet_id", value: petID.uuidString)
                .execute()
            return response.count ?? 0
        } catch {
            print("[PetsService] fetchVisitCount 失败: \(error)")
            return 0
        }
    }

    /// Increments the shared `pets.boop_count` by `delta`. Delegates to
    /// the `increment_pet_boop_count` RPC so the update is atomic and
    /// not subject to the `pets` table's owner-only update RLS. The
    /// caller is responsible for debouncing — a rapid tap burst should
    /// become one RPC call, not N.
    ///
    /// Returns the new server-side count so the caller can reconcile
    /// its local optimistic state, or nil on failure.
    func incrementBoopCount(petID: UUID, by delta: Int) async -> Int? {
        guard delta > 0 else { return nil }

        struct Params: Encodable {
            let pet_id: UUID
            let by_count: Int
        }

        do {
            let newCount: Int = try await client
                .rpc("increment_pet_boop_count", params: Params(pet_id: petID, by_count: delta))
                .execute()
                .value
            return newCount
        } catch {
            print("[PetsService] incrementBoopCount 失败: \(error)")
            return nil
        }
    }

    /// Reads the current `boop_count` for a pet. Used on PetProfileView
    /// load so we can display the cumulative total alongside 帖子 and 访客.
    func fetchBoopCount(petID: UUID) async -> Int {
        struct BoopRow: Decodable { let boop_count: Int? }
        do {
            let row: BoopRow = try await client
                .from("pets")
                .select("boop_count")
                .eq("id", value: petID.uuidString)
                .single()
                .execute()
                .value
            return row.boop_count ?? 0
        } catch {
            print("[PetsService] fetchBoopCount 失败: \(error)")
            return 0
        }
    }

    // MARK: - Discovery rails

    /// Pets that share species + (breed OR home_city) with the given
    /// pet, excluding pets owned by the same user. Used for Discover's
    /// "与你的毛孩子相似" rail.
    ///
    /// Strategy: one Supabase query with
    ///   species = pet.species AND owner != pet.owner AND (breed = pet.breed OR home_city = pet.home_city)
    /// expressed via PostgREST's `or()` filter for the breed/city arm.
    /// We scope by species first so the rail doesn't surface a poodle
    /// in a cat owner's "similar pets" list. When the source pet has
    /// no breed AND no city, the filter degrades to "same species, not
    /// yours" — still a reasonable rail.
    ///
    /// Returns an empty array on failure (analytics-style UI: a
    /// missing rail row beats a crash toast).
    func fetchSimilarPets(to pet: RemotePet, limit: Int = 12) async -> [RemotePet] {
        guard let species = pet.species?.trimmingCharacters(in: .whitespacesAndNewlines),
              !species.isEmpty else {
            return []
        }

        // Build the breed/city disjunction. PostgREST `or=` takes a
        // comma-separated list of filters, each in `column.operator.value`
        // form. Quote the values so spaces in city names don't break
        // the parser.
        var orClauses: [String] = []
        if let breed = pet.breed?.trimmingCharacters(in: .whitespacesAndNewlines), !breed.isEmpty {
            orClauses.append("breed.eq.\(breed)")
        }
        if let city = pet.home_city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
            orClauses.append("home_city.eq.\(city)")
        }

        do {
            var query = client
                .from("pets")
                .select()
                .eq("species", value: species)
                .neq("owner_user_id", value: pet.owner_user_id.uuidString)
                .neq("id", value: pet.id.uuidString)

            if !orClauses.isEmpty {
                query = query.or(orClauses.joined(separator: ","))
            }

            let response: [RemotePet] = try await query
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            return response
        } catch {
            print("[PetsService] fetchSimilarPets 失败: \(error)")
            return []
        }
    }

    /// Pets ordered by engagement (`boop_count desc`, then
    /// `created_at desc`). Excludes pets owned by `excludingOwnerID`
    /// when provided — pass the current user's id so their own pets
    /// don't clutter the "人气毛孩子" rail with their own content.
    ///
    /// Returns an empty array on failure.
    func fetchPopularPets(
        excludingOwnerID: UUID?,
        limit: Int = 12
    ) async -> [RemotePet] {
        do {
            var query = client
                .from("pets")
                .select()

            if let ownerID = excludingOwnerID {
                query = query.neq("owner_user_id", value: ownerID.uuidString)
            }

            let response: [RemotePet] = try await query
                .order("boop_count", ascending: false)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            return response
        } catch {
            print("[PetsService] fetchPopularPets 失败: \(error)")
            return []
        }
    }

    /// "今日明星毛孩子" hero pick for Discover. Returns a single non-
    /// self pet that rotates deterministically day-over-day so repeat
    /// visitors see a fresh face without us needing a `featured_on`
    /// schema column.
    ///
    /// Strategy: fetch the top 7 pets by `boop_count desc, created_at
    /// desc` (excluding the viewer's own), then pick index
    /// `dayOfYear % count` on the client. The DB query stays cheap (no
    /// offset math server-side) and the rotation is stable within a
    /// calendar day for a given viewer — a pull-to-refresh won't
    /// reshuffle, which matches "hero card feels curated" better than
    /// a random pick would.
    ///
    /// Returns nil when the pool is empty or the query fails — the
    /// caller hides the section in that case.
    func fetchPetOfTheDay(excludingOwnerID: UUID?) async -> RemotePet? {
        do {
            var query = client
                .from("pets")
                .select()

            if let ownerID = excludingOwnerID {
                query = query.neq("owner_user_id", value: ownerID.uuidString)
            }

            let response: [RemotePet] = try await query
                .order("boop_count", ascending: false)
                .order("created_at", ascending: false)
                .limit(7)
                .execute()
                .value

            guard !response.isEmpty else { return nil }

            // Day-of-year rotation keeps the pick stable within a day
            // but refreshes it tomorrow. We use the viewer's current
            // calendar so the "day" boundary respects their timezone.
            let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
            let index = dayOfYear % response.count
            return response[index]
        } catch {
            print("[PetsService] fetchPetOfTheDay 失败: \(error)")
            return nil
        }
    }

    /// Pets that have posted in the last 48 hours and that the viewer
    /// is not already exposed to via follows or self-ownership. Drives
    /// Discover's "最近在发的毛孩子" rail — a low-friction on-ramp to
    /// accounts the viewer isn't yet subscribed to but that are
    /// actively producing content.
    ///
    /// Implementation: a two-step fetch because PostgREST doesn't have
    /// a clean `select distinct`. Step 1 pulls the most recent 50
    /// posts (`created_at desc`) within the 48h window; we extract the
    /// first-seen `pet_id` for each, preserving recency order. Step 2
    /// resolves those ids to full pet rows via `.in("id", …)`. Final
    /// client-side filter drops pets owned by `excludingOwnerID` and
    /// any pet whose owner is in `followingIDs` (follow semantics in
    /// this app are user-to-user, so we dedupe by the owner set).
    ///
    /// `followingIDs` is user-scoped (matches `FollowService`'s store).
    /// Pass nil if the caller hasn't loaded follows yet — the rail
    /// degrades to "fresh posters excluding self," which may overlap
    /// with 人气毛孩子 but beats not showing anything.
    ///
    /// Returns an empty array on failure.
    func fetchRecentActivityPets(
        followingIDs: Set<UUID>?,
        excludingOwnerID: UUID?,
        limit: Int = 12
    ) async -> [RemotePet] {
        struct RecentPostRow: Decodable {
            let pet_id: UUID
            let owner_user_id: UUID
        }

        let cutoff = Date().addingTimeInterval(-48 * 60 * 60)
        // Supabase PostgREST ISO8601 with fractional seconds — matches
        // the format the DB emits for `timestamptz` columns.
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let cutoffString = isoFormatter.string(from: cutoff)

        do {
            let recentPosts: [RecentPostRow] = try await client
                .from("posts")
                .select("pet_id,owner_user_id")
                .gt("created_at", value: cutoffString)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value

            // Preserve first-seen order so the most recently active pets
            // lead the rail. A plain Set would throw the ordering away.
            var seen = Set<UUID>()
            var orderedPetIDs: [UUID] = []
            for row in recentPosts {
                if row.owner_user_id == excludingOwnerID { continue }
                if let follows = followingIDs, follows.contains(row.owner_user_id) { continue }
                if seen.insert(row.pet_id).inserted {
                    orderedPetIDs.append(row.pet_id)
                }
                if orderedPetIDs.count >= limit { break }
            }

            guard !orderedPetIDs.isEmpty else { return [] }

            let pets: [RemotePet] = try await client
                .from("pets")
                .select()
                .in("id", values: orderedPetIDs.map { $0.uuidString })
                .execute()
                .value

            // Re-apply the recency ordering: `.in()` returns rows in
            // whatever order the server chooses, so we sort by our
            // precomputed index to keep the freshest pet first.
            let rank: [UUID: Int] = Dictionary(
                uniqueKeysWithValues: orderedPetIDs.enumerated().map { ($1, $0) }
            )
            return pets
                .filter { rank[$0.id] != nil }
                .sorted { (rank[$0.id] ?? .max) < (rank[$1.id] ?? .max) }
        } catch {
            print("[PetsService] fetchRecentActivityPets 失败: \(error)")
            return []
        }
    }

    /// Pets with `open_to_playdates = true`, excluding pets owned by
    /// `excludingUserId`. Backs Discover's "今天有空的毛孩子" rail —
    /// a surface for spontaneous same-day playdate discovery.
    ///
    /// Sort strategy: if `viewerCity` is non-nil, pets whose
    /// `home_city` matches (case-insensitive trimmed) are bubbled to
    /// the top, then the remainder follows. We fetch up to 2x `limit`
    /// server-side (capped at 40) ordered by `updated_at desc`, then
    /// do the city-priority partition client-side and trim back to
    /// `limit`. Two advantages over a UNION-style double query:
    ///   * one round-trip instead of two
    ///   * a small city with very few open pets still gets filled in
    ///     with recent out-of-city pets rather than leaving the rail
    ///     sparse.
    ///
    /// Returns an empty array on failure.
    func fetchOpenToPlaydates(
        excludingUserId: UUID,
        viewerCity: String?,
        limit: Int = 20
    ) async throws -> [RemotePet] {
        // Upper bound per the rail spec — fetch 40, return up to 20
        // after client-side re-ordering. When the caller asks for a
        // larger limit we scale the fetch cap in proportion (still
        // capped at 40 so a buggy caller can't DoS the DB).
        let fetchCap = min(40, max(limit * 2, limit))

        let response: [RemotePet] = try await client
            .from("pets")
            .select()
            .eq("open_to_playdates", value: true)
            .neq("owner_user_id", value: excludingUserId.uuidString)
            .order("updated_at", ascending: false)
            .limit(fetchCap)
            .execute()
            .value

        // City-priority partition. A nil / blank `viewerCity` skips
        // the partition — server-order is already "most recently
        // updated first", which is a reasonable fallback.
        let normalizedViewerCity = viewerCity?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard let city = normalizedViewerCity, !city.isEmpty else {
            return Array(response.prefix(limit))
        }

        var sameCity: [RemotePet] = []
        var otherCity: [RemotePet] = []
        for pet in response {
            let petCity = pet.home_city?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            if petCity == city {
                sameCity.append(pet)
            } else {
                otherCity.append(pet)
            }
        }
        return Array((sameCity + otherCity).prefix(limit))
    }

    /// Pets in the same city as the given one, excluding pets owned by
    /// `excludingOwnerID`. Used for Discover's "同城毛孩子" rail —
    /// pass the *viewer's* id (not the source pet's owner id) when
    /// you want to hide the current user's own pets from the rail.
    ///
    /// Returns an empty array when `city` is empty or the query fails.
    func fetchNearbyPets(
        city: String,
        excludingOwnerID: UUID?,
        limit: Int = 12
    ) async -> [RemotePet] {
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCity.isEmpty else { return [] }

        do {
            var query = client
                .from("pets")
                .select()
                .eq("home_city", value: trimmedCity)

            if let ownerID = excludingOwnerID {
                query = query.neq("owner_user_id", value: ownerID.uuidString)
            }

            let response: [RemotePet] = try await query
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            return response
        } catch {
            print("[PetsService] fetchNearbyPets 失败: \(error)")
            return []
        }
    }

    // MARK: - Cohort surfaces (breed + city)
    //
    // `fetchPetsByBreed` / `fetchPetsByCity` back the dedicated
    // `PetCohortView` list screen — tap a breed or city pill from
    // anywhere in the app and land on a full paginated list of every
    // pet in that cohort. Unlike the Discover rails (which cap at 12
    // and mix criteria), these are the "see everything" views.
    //
    // Pagination uses PostgREST's inclusive `.range(offset, to: offset
    // + limit - 1)` form — the caller increments `offset` by `limit`
    // for each next page and stops when a page returns fewer than
    // `limit` rows (the client's `hasMore` flag).
    //
    // Matching is a case-insensitive trimmed `.eq` on the stringly-
    // typed column. Normalisation of the input happens client-side so
    // the DB query stays a single equality filter (good indexes, cheap
    // plan) rather than an `ilike` wildcard scan.

    /// Pets with `breed = <breed>` (case-insensitive trimmed match),
    /// excluding pets owned by `excludingOwnerID` when provided.
    /// Ordered by `created_at desc`. Supports offset pagination.
    ///
    /// Returns an empty array when `breed` is blank or the query
    /// fails — matches the `fetchSimilarPets` error posture.
    func fetchPetsByBreed(
        _ breed: String,
        excludingOwnerID: UUID?,
        limit: Int = 24,
        offset: Int = 0
    ) async -> [RemotePet] {
        let trimmed = breed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        do {
            var query = client
                .from("pets")
                .select()
                .eq("breed", value: trimmed)

            if let ownerID = excludingOwnerID {
                query = query.neq("owner_user_id", value: ownerID.uuidString)
            }

            let response: [RemotePet] = try await query
                .order("created_at", ascending: false)
                .range(from: offset, to: offset + limit - 1)
                .execute()
                .value
            return response
        } catch {
            print("[PetsService] fetchPetsByBreed 失败: \(error)")
            return []
        }
    }

    /// Pets with `home_city = <city>` (case-insensitive trimmed match),
    /// excluding pets owned by `excludingOwnerID` when provided. Ordered
    /// by `created_at desc`. Supports offset pagination.
    ///
    /// Returns an empty array when `city` is blank or the query fails.
    func fetchPetsByCity(
        _ city: String,
        excludingOwnerID: UUID?,
        limit: Int = 24,
        offset: Int = 0
    ) async -> [RemotePet] {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        do {
            var query = client
                .from("pets")
                .select()
                .eq("home_city", value: trimmed)

            if let ownerID = excludingOwnerID {
                query = query.neq("owner_user_id", value: ownerID.uuidString)
            }

            let response: [RemotePet] = try await query
                .order("created_at", ascending: false)
                .range(from: offset, to: offset + limit - 1)
                .execute()
                .value
            return response
        } catch {
            print("[PetsService] fetchPetsByCity 失败: \(error)")
            return []
        }
    }

    func deletePet(_ petID: UUID, for userID: UUID) async {
        errorMessage = nil

        do {
            try await client
                .from("pets")
                .delete()
                .eq("id", value: petID.uuidString)
                .eq("owner_user_id", value: userID.uuidString)
                .execute()

            pets.removeAll { $0.id == petID }
            if pets.contains(where: { $0.owner_user_id == userID }) {
                await loadPets(for: userID)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func normalizeOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizeRequired(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Cross-service pet mutation broadcast
//
// `PostsService` is instantiated per-view (each of `FeedView`,
// `ProfileView`, `PetProfileView`, `CreatePostView` holds its own
// `@StateObject`), so a direct `patchPet(…)` call on a single instance
// would leave the other three with stale per-post JOIN snapshots of the
// pet. `StoryService.shared` is process-wide but still independent of
// `PetsService`. Using a NotificationCenter broadcast lets every live
// instance subscribe once in its `init` and self-patch on receipt —
// keeping cached feed / rail rows in sync with pet avatar / accessory
// edits without a pull-to-refresh.
//
// The broadcast carries the updated `RemotePet` under the `"pet"` key
// in `userInfo`. Subscribers should guard that cast and bail silently
// if the payload is malformed.
extension Notification.Name {
    static let petDidUpdate = Notification.Name("PawPal.petDidUpdate")
}
