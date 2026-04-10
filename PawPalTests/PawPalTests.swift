import Foundation
import SwiftData
import Testing
@testable import PetHealth

struct PetHealthTests {
    @Test func storedPetProfilesCanBeFetchedNewestFirst() throws {
        let container = try ModelContainer(
            for: StoredPetProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let olderPet = StoredPetProfile(
            createdAt: Date(timeIntervalSince1970: 10),
            name: "Older",
            species: "Dog",
            breed: "Corgi",
            age: "4",
            weight: "20 lb",
            notes: ""
        )
        let newerPet = StoredPetProfile(
            createdAt: Date(timeIntervalSince1970: 20),
            name: "Newer",
            species: "Cat",
            breed: "Tabby",
            age: "2",
            weight: "9 lb",
            notes: ""
        )

        context.insert(olderPet)
        context.insert(newerPet)
        try context.save()

        let descriptor = FetchDescriptor<StoredPetProfile>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let pets = try context.fetch(descriptor)

        #expect(pets.map(\.name) == ["Newer", "Older"])
    }

    @Test func storedPetProfileConvertsToPetProfile() {
        let createdAt = Date(timeIntervalSince1970: 123)
        let storedPet = StoredPetProfile(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            createdAt: createdAt,
            name: "Mochi",
            species: "Dog",
            breed: "Shiba",
            age: "3",
            weight: "22 lb",
            notes: "Loves carrots"
        )

        let pet = storedPet.toPetProfile()

        #expect(pet.name == "Mochi")
        #expect(pet.species == "Dog")
        #expect(pet.breed == "Shiba")
        #expect(pet.age == "3")
        #expect(pet.weight == "22 lb")
        #expect(pet.notes == "Loves carrots")
    }
}
