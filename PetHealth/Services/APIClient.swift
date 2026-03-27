import Foundation

final class APIClient {
    private let baseURL = URL(string: "http://127.0.0.1:8001")!

    func analyze(
        pet: PetProfile,
        symptomText: String,
        durationText: String,
        extraNotes: String
    ) async throws -> AnalysisResult {
        let endpoint = baseURL.appendingPathComponent("analyze")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = AnalyzeRequest(
            pet: pet,
            symptomText: symptomText,
            durationText: durationText,
            extraNotes: extraNotes
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: message])
        }

        return try JSONDecoder().decode(AnalysisResult.self, from: data)
    }
}

private struct AnalyzeRequest: Codable {
    let pet: PetProfile
    let symptomText: String
    let durationText: String
    let extraNotes: String
}
