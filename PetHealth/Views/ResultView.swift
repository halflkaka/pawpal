import SwiftUI
import SwiftData

struct ResultView: View {
    @Environment(\.modelContext) private var modelContext

    let pet: StoredPetProfile?
    let petName: String
    let symptomText: String
    let durationText: String
    let extraNotes: String
    let result: AnalysisResult

    @State private var didSave = false

    init(
        pet: StoredPetProfile? = nil,
        petName: String = "",
        symptomText: String,
        durationText: String,
        extraNotes: String,
        result: AnalysisResult
    ) {
        self.pet = pet
        self.petName = petName
        self.symptomText = symptomText
        self.durationText = durationText
        self.extraNotes = extraNotes
        self.result = result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                urgencyCard
                detailCard(title: "Summary", items: [result.summary], tint: .blue)
                detailCard(title: "Possible Causes", items: result.possibleCauses, tint: .indigo)
                detailCard(title: "What To Do Now", items: result.nextSteps, tint: .green)
                detailCard(title: "Red Flags", items: result.redFlags, tint: .red)
                actionsCard
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var urgencyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Urgency")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack {
                Text(result.urgency.capitalized)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(urgencyColor)
                Spacer()
            }

            if !petName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(petName, systemImage: "pawprint.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(urgencyDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(urgencyColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.headline)

            Button(didSave ? "Saved" : "Save Check") {
                saveCheck()
            }
            .buttonStyle(.borderedProminent)
            .disabled(didSave)

            NavigationLink {
                VetFinderView()
            } label: {
                Label("Find Nearby Vet", systemImage: "cross.case.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func detailCard(title: String, items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 10, height: 10)
                Text(title)
                    .font(.headline)
            }

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(tint)
                        .frame(width: 6, height: 6)
                        .padding(.top, 7)
                    Text(item)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var urgencyColor: Color {
        switch result.urgency {
        case "emergency": return .red
        case "soon": return .orange
        default: return .blue
        }
    }

    private var urgencyDescription: String {
        switch result.urgency {
        case "emergency":
            return "These symptoms may need urgent veterinary attention right away."
        case "soon":
            return "This does not clearly sound like an emergency, but timely veterinary follow-up is a good idea."
        default:
            return "This may be reasonable to monitor, as long as symptoms do not worsen."
        }
    }

    private func saveCheck() {
        let stored = StoredSymptomCheck(
            petID: pet?.id,
            petName: petName,
            symptomText: symptomText,
            durationText: durationText,
            extraNotes: extraNotes,
            urgency: result.urgency,
            summary: result.summary,
            possibleCausesJSON: StoredSymptomCheck.encode(result.possibleCauses),
            nextStepsJSON: StoredSymptomCheck.encode(result.nextSteps),
            redFlagsJSON: StoredSymptomCheck.encode(result.redFlags)
        )
        modelContext.insert(stored)
        didSave = true
    }
}
