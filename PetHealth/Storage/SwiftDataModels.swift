import Foundation
import SwiftData

@Model
final class StoredPetProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var species: String
    var breed: String
    var age: String
    var weight: String
    var notes: String

    init(
        id: UUID = UUID(),
        name: String,
        species: String,
        breed: String,
        age: String,
        weight: String,
        notes: String
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

@Model
final class StoredSymptomCheck {
    @Attribute(.unique) var id: UUID
    var date: Date
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
        self.symptomText = symptomText
        self.durationText = durationText
        self.extraNotes = extraNotes
        self.urgency = urgency
        self.summary = summary
        self.possibleCausesJSON = possibleCausesJSON
        self.nextStepsJSON = nextStepsJSON
        self.redFlagsJSON = redFlagsJSON
    }
}
