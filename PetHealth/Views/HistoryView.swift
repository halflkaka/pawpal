import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        List(viewModel.checks) { check in
            NavigationLink {
                ResultView(
                    symptomText: check.symptomText,
                    durationText: check.durationText,
                    extraNotes: check.extraNotes,
                    result: check.result,
                    historyViewModel: viewModel
                )
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(check.symptomText)
                        .font(.headline)
                    Text(check.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(check.result.urgency.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("History")
    }
}
