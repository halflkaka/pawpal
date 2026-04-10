import Foundation

struct PetProfile: Identifiable, Codable {
    let id: UUID
    var name: String
    var species: String
    var breed: String
    var age: String
    var weight: String
    var notes: String

    init(
        id: UUID = UUID(),
        name: String = "",
        species: String = "Dog",
        breed: String = "",
        age: String = "",
        weight: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.species = species
        self.breed = breed
        self.age = age
        self.weight = weight
        self.notes = notes
    }
}
