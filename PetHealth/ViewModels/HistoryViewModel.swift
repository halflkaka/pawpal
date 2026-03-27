import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var checks: [SymptomCheck] = [
        SymptomCheck(
            symptomText: "Vomiting twice since this morning",
            durationText: "Since this morning",
            extraNotes: "Still drinking water",
            result: .mock
        )
    ]

    func addCheck(_ check: SymptomCheck) {
        checks.insert(check, at: 0)
    }
}
