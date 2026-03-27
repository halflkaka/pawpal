import SwiftUI

struct ResultView: View {
    let symptomText: String
    let durationText: String
    let extraNotes: String
    let result: AnalysisResult
    @ObservedObject var historyViewModel: HistoryViewModel

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
                Button("Save Check") {
                    let check = SymptomCheck(
                        symptomText: symptomText,
                        durationText: durationText,
                        extraNotes: extraNotes,
                        result: result
                    )
                    historyViewModel.addCheck(check)
                }

                NavigationLink("Find Nearby Vet") {
                    VetFinderView()
                }
            }
        }
        .navigationTitle("Result")
    }
}
