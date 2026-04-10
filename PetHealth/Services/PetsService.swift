import Foundation
import Supabase

@MainActor
final class PetsService: ObservableObject {
    @Published var pets: [RemotePet] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let client: SupabaseClient

    init() {
        guard let url = URL(string: SupabaseConfig.urlString) else {
            fatalError("Invalid Supabase URL")
        }
        client = SupabaseClient(supabaseURL: url, supabaseKey: SupabaseConfig.anonKey)
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
            let species: String
            let breed: String
            let sex: String
            let age_text: String
            let weight: String
            let home_city: String
            let bio: String
        }

        let payload = NewPet(
            owner_user_id: userID,
            name: name,
            species: species,
            breed: breed,
            sex: sex,
            age_text: age,
            weight: weight,
            home_city: homeCity,
            bio: bio
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
            let species: String
            let breed: String
            let sex: String
            let age_text: String
            let weight: String
            let home_city: String
            let bio: String
        }

        errorMessage = nil

        let payload = PetUpdate(
            name: pet.name,
            species: pet.species ?? "",
            breed: pet.breed ?? "",
            sex: pet.sex ?? "",
            age_text: pet.age ?? "",
            weight: pet.weight ?? "",
            home_city: pet.home_city ?? "",
            bio: pet.bio ?? ""
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
                .execute()
            await loadPets(for: userID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
