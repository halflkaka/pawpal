import SwiftUI

struct SymptomCheckView: View {
    let pet: PetProfile
    @ObservedObject var historyViewModel: HistoryViewModel
    @StateObject private var viewModel = SymptomCheckViewModel()
    @State private var navigateToResult = false

    var body: some View {
        Form {
            Section("Symptoms") {
                TextField("What’s going on?", text: $viewModel.symptomText, axis: .vertical)
                    .lineLimit(3...6)
                TextField("When did it start?", text: $viewModel.durationText)
                TextField("Anything else?", text: $viewModel.extraNotes, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section {
                Button {
                    Task {
                        await viewModel.analyze(using: pet)
                        if viewModel.result != nil {
                            navigateToResult = true
                        }
                    }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Text("Analyze")
                    }
                }
                .disabled(viewModel.symptomText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
            }

            if let errorMessage = viewModel.errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Symptom Check")
        .navigationDestination(isPresented: $navigateToResult) {
            if let result = viewModel.result {
                ResultView(
                    symptomText: viewModel.symptomText,
                    durationText: viewModel.durationText,
                    extraNotes: viewModel.extraNotes,
                    result: result,
                    historyViewModel: historyViewModel
                )
            }
        }
    }
}
