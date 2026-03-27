import SwiftUI
import SwiftData

struct HistoryView: View {
    let selectedPetID: UUID?

    @Query(sort: \StoredSymptomCheck.date, order: .reverse) private var checks: [StoredSymptomCheck]

    private var filteredChecks: [StoredSymptomCheck] {
        guard let selectedPetID else { return checks }
        return checks.filter { check in
            if let petID = check.petID {
                return petID == selectedPetID
            }
            return true
        }
    }

    var body: some View {
        ScrollView {
            if filteredChecks.isEmpty {
                ContentUnavailableView(
                    "No Saved Checks",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Saved symptom checks will appear here.")
                )
                .padding(.top, 80)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(filteredChecks) { check in
                        NavigationLink {
                            ResultView(
                                petName: check.petName,
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

                                if !check.petName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Label(check.petName, systemImage: "pawprint.fill")
                                        .font(.caption.weight(.semibold))
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
