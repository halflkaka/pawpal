import Foundation
import SwiftData

@Model
final class StoredPetProfile {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var name: String
    var species: String
    var breed: String
    var age: String
    var weight: String
    var notes: String

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        name: String,
        species: String,
        breed: String,
        age: String,
        weight: String,
        notes: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
        self.species = species
        self.breed = breed
        self.age = age
        self.weight = weight
        self.notes = notes
    }

    func toPetProfile() -> PetProfile {
        PetProfile(
            id: id,
            name: name,
            species: species,
            breed: breed,
            age: age,
            weight: weight,
            notes: notes
        )
    }
}

@Model
final class StoredSymptomCheck {
    @Attribute(.unique) var id: UUID
    var date: Date
    var petID: UUID?
    var petName: String
    var symptomText: String
    var durationText: String
    var extraNotes: String
    var urgency: String
    var summary: String
    var possibleCausesJSON: String
    var nextStepsJSON: String
    var redFlagsJSON: String

    init(
        id: UUID = UUID(),
        date: Date = .now,
        petID: UUID? = nil,
        petName: String = "",
        symptomText: String,
        durationText: String,
        extraNotes: String,
        urgency: String,
        summary: String,
        possibleCausesJSON: String,
        nextStepsJSON: String,
        redFlagsJSON: String
    ) {
        self.id = id
        self.date = date
        self.petID = petID
        self.petName = petName
        self.symptomText = symptomText
        self.durationText = durationText
        self.extraNotes = extraNotes
        self.urgency = urgency
        self.summary = summary
        self.possibleCausesJSON = possibleCausesJSON
        self.nextStepsJSON = nextStepsJSON
        self.redFlagsJSON = redFlagsJSON
    }

    func toAnalysisResult() -> AnalysisResult {
        AnalysisResult(
            urgency: urgency,
            possibleCauses: Self.decode(possibleCausesJSON),
            nextSteps: Self.decode(nextStepsJSON),
            redFlags: Self.decode(redFlagsJSON),
            vetRecommended: urgency != "monitor",
            summary: summary
        )
    }

    static func encode(_ values: [String]) -> String {
        let data = (try? JSONEncoder().encode(values)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    static func decode(_ value: String) -> [String] {
        guard let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }
}

@Model
final class StoredPost {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var petID: UUID?
    var petName: String
    var caption: String
    var mood: String
    var imageSlotCount: Int

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        petID: UUID? = nil,
        petName: String = "",
        caption: String,
        mood: String,
        imageSlotCount: Int = 0
    ) {
        self.id = id
        self.createdAt = createdAt
        self.petID = petID
        self.petName = petName
        self.caption = caption
        self.mood = mood
        self.imageSlotCount = imageSlotCount
    }
}
