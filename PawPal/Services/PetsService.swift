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
        avatarData: Data? = nil
    ) async -> RemotePet? {
        struct NewPet: Encodable {
            let owner_user_id: UUID
            let name: String
            let species: String?
            let breed: String?
            let sex: String?
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

    func updatePet(_ pet: RemotePet, for userID: UUID, avatarData: Data? = nil) async {
        struct PetUpdate: Encodable {
            let name: String
            let species: String?
            let breed: String?
            let sex: String?
            let age_text: String?
            let weight: String?
            let home_city: String?
            let bio: String?
            let avatar_url: String?
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

        let payload = PetUpdate(
            name: normalizeRequired(pet.name),
            species: normalizeOptional(pet.species),
            breed: normalizeOptional(pet.breed),
            sex: normalizeOptional(pet.sex),
            age_text: normalizeOptional(pet.age),
            weight: normalizeOptional(pet.weight),
            home_city: normalizeOptional(pet.home_city),
            bio: normalizeOptional(pet.bio),
            avatar_url: updatedAvatarURL
        )

        do {
            try await client
                .from("pets")
                .update(payload)
                .eq("id", value: pet.id.uuidString)
                .execute()
            await loadPets(for: userID)
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
