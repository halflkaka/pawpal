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

    func addPet(for userID: UUID, name: String, species: String, breed: String, age: String, weight: String, notes: String) async {
        struct NewPet: Encodable {
            let owner_user_id: UUID
            let name: String
            let species: String
            let breed: String
            let age: String
            let weight: String
            let notes: String
        }

        let payload = NewPet(
            owner_user_id: userID,
            name: name,
            species: species,
            breed: breed,
            age: age,
            weight: weight,
            notes: notes
        )

        do {
            try await client
                .from("pets")
                .insert(payload)
                .execute()
            await loadPets(for: userID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
