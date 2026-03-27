import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \StoredSymptomCheck.date, order: .reverse) private var checks: [StoredSymptomCheck]

    var body: some View {
        List(checks) { check in
            NavigationLink {
                ResultView(
                    symptomText: check.symptomText,
                    durationText: check.durationText,
                    extraNotes: check.extraNotes,
                    result: check.toAnalysisResult()
                )
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(check.symptomText)
                        .font(.headline)
                    Text(check.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(check.urgency.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("History")
        .overlay {
            if checks.isEmpty {
                ContentUnavailableView("No Saved Checks", systemImage: "clock.arrow.circlepath", description: Text("Saved symptom checks will appear here."))
            }
        }
    }
}
