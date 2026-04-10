import Foundation

@MainActor
final class SymptomCheckViewModel: ObservableObject {
    @Published var symptomText = ""
    @Published var durationText = ""
    @Published var extraNotes = ""
    @Published var isLoading = false
    @Published var result: AnalysisResult?
    @Published var errorMessage: String?

    private let apiClient = APIClient()

    func analyze(using pet: PetProfile) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            result = try await apiClient.analyze(
                pet: pet,
                symptomText: symptomText,
                durationText: durationText,
                extraNotes: extraNotes
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
