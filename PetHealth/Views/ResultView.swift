import SwiftUI
import SwiftData

struct ResultView: View {
    @Environment(\.modelContext) private var modelContext

    let symptomText: String
    let durationText: String
    let extraNotes: String
    let result: AnalysisResult

    @State private var didSave = false

    var body: some View {
        List {
            Section("Urgency") {
                Text(result.urgency.capitalized)
                    .font(.title3.bold())
            }

            Section("Summary") {
                Text(result.summary)
            }

            Section("Possible Causes") {
                ForEach(result.possibleCauses, id: \.self) { cause in
                    Text(cause)
                }
            }

            Section("What To Do Now") {
                ForEach(result.nextSteps, id: \.self) { step in
                    Text(step)
                }
            }

            Section("Red Flags") {
                ForEach(result.redFlags, id: \.self) { flag in
                    Text(flag)
                }
            }

            Section("Actions") {
                Button(didSave ? "Saved" : "Save Check") {
                    saveCheck()
                }
                .disabled(didSave)

                NavigationLink("Find Nearby Vet") {
                    VetFinderView()
                }
            }
        }
        .navigationTitle("Result")
    }

    private func saveCheck() {
        let stored = StoredSymptomCheck(
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
