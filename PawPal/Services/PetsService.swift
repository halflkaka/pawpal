import Foundation
import Supabase

@MainActor
final class PetsService: ObservableObject {
    @Published var pets: [RemotePet] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let client: SupabaseClient

    init() {
        client = SupabaseConfig.client
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

    func addPet(for userID: UUID, name: String, species: String, breed: String, sex: String, age: String, weight: String, homeCity: String, bio: String) async -> RemotePet? {
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
            let pet: RemotePet = try await client
                .from("pets")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value

            pets = [pet] + pets.filter { $0.id != pet.id }
            return pet
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updatePet(_ pet: RemotePet, for userID: UUID) async {
        struct PetUpdate: Encodable {
            let name: String
            let species: String?
            let breed: String?
            let sex: String?
            let age_text: String?
            let weight: String?
            let home_city: String?
            let bio: String?
        }

        errorMessage = nil

        let payload = PetUpdate(
            name: normalizeRequired(pet.name),
            species: normalizeOptional(pet.species),
            breed: normalizeOptional(pet.breed),
            sex: normalizeOptional(pet.sex),
            age_text: normalizeOptional(pet.age),
            weight: normalizeOptional(pet.weight),
            home_city: normalizeOptional(pet.home_city),
            bio: normalizeOptional(pet.bio)
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
