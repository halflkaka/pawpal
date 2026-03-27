import Foundation

struct SymptomCheck: Identifiable, Codable {
    let id: UUID
    let date: Date
    var symptomText: String
    var durationText: String
    var extraNotes: String
    var result: AnalysisResult

    init(
        id: UUID = UUID(),
        date: Date = .now,
        symptomText: String,
        durationText: String,
        extraNotes: String,
        result: AnalysisResult
    ) {
        self.id = id
        self.date = date
        self.symptomText = symptomText
        self.durationText = durationText
        self.extraNotes = extraNotes
        self.result = result
    }
}
