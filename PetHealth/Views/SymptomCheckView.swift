import SwiftUI

struct SymptomCheckView: View {
    let pet: StoredPetProfile?
    @StateObject private var viewModel = SymptomCheckViewModel()
    @State private var navigateToResult = false

    private let quickSymptoms = [
        "Vomiting",
        "Diarrhea",
        "Itchy skin",
        "Limping",
        "Not eating",
        "Low energy"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                introCard
                quickSymptomsSection
                formCard
                analyzeSection
                errorSection
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Symptom Check")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToResult) {
            if let result = viewModel.result {
                ResultView(
                    symptomText: viewModel.symptomText,
                    durationText: viewModel.durationText,
                    extraNotes: viewModel.extraNotes,
                    result: result
                )
            }
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What’s going on?")
                .font(.title2.bold())
            Text("Describe your pet’s symptoms in a few words, then add anything important like timing, appetite, energy, or behavior changes.")
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var quickSymptomsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Add")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                ForEach(quickSymptoms, id: \.self) { symptom in
                    Button {
                        appendSymptom(symptom)
                    } label: {
                        Text(symptom)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue.opacity(0.10))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Details")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Symptoms")
                    .font(.subheadline.weight(.semibold))
                TextField("Vomiting twice today and low energy", text: $viewModel.symptomText, axis: .vertical)
                    .lineLimit(4...8)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("When did it start?")
                    .font(.subheadline.weight(.semibold))
                TextField("Since this morning", text: $viewModel.durationText)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Extra notes")
                    .font(.subheadline.weight(.semibold))
                TextField("Still drinking water, no coughing, seems tired", text: $viewModel.extraNotes, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var analyzeSection: some View {
        Button {
            Task {
                await viewModel.analyze(using: pet?.toPetProfile() ?? PetProfile())
                if viewModel.result != nil {
                    navigateToResult = true
                }
            }
        } label: {
            HStack {
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Label("Analyze", systemImage: "sparkles")
                        .font(.headline)
                }
                Spacer()
            }
            .padding()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(viewModel.symptomText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage = viewModel.errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Text("Couldn’t analyze right now")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func appendSymptom(_ symptom: String) {
        if viewModel.symptomText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            viewModel.symptomText = symptom
        } else if !viewModel.symptomText.localizedCaseInsensitiveContains(symptom) {
            viewModel.symptomText += ", \(symptom.lowercased())"
        }
    }
}
