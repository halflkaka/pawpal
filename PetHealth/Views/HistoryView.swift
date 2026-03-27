import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \StoredSymptomCheck.date, order: .reverse) private var checks: [StoredSymptomCheck]

    var body: some View {
        ScrollView {
            if checks.isEmpty {
                ContentUnavailableView(
                    "No Saved Checks",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Saved symptom checks will appear here.")
                )
                .padding(.top, 80)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(checks) { check in
                        NavigationLink {
                            ResultView(
                                symptomText: check.symptomText,
                                durationText: check.durationText,
                                extraNotes: check.extraNotes,
                                result: check.toAnalysisResult()
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(check.urgency.capitalized)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(urgencyColor(for: check.urgency).opacity(0.14))
                                        .foregroundStyle(urgencyColor(for: check.urgency))
                                        .clipShape(Capsule())

                                    Spacer()

                                    Text(check.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Text(check.symptomText)
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Text(check.summary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("History")
    }

    private func urgencyColor(for urgency: String) -> Color {
        switch urgency {
        case "emergency": return .red
        case "soon": return .orange
        default: return .blue
        }
    }
}
