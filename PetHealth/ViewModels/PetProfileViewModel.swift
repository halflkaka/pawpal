import Foundation

@MainActor
final class PetProfileViewModel: ObservableObject {
    @Published var pet = PetProfile(
        name: "Mochi",
        species: "Dog",
        breed: "Corgi",
        age: "5",
        weight: "24 lb",
        notes: "Sensitive stomach"
    )
}
