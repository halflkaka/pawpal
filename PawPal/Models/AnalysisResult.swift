import Foundation

struct AnalysisResult: Codable {
    var urgency: String
    var possibleCauses: [String]
    var nextSteps: [String]
    var redFlags: [String]
    var vetRecommended: Bool
    var summary: String

    static let mock = AnalysisResult(
        urgency: "soon",
        possibleCauses: [
            "Mild stomach upset",
            "Dietary indiscretion"
        ],
        nextSteps: [
            "Monitor hydration and energy level closely",
            "Avoid giving human medications",
            "Consider a vet visit if symptoms continue"
        ],
        redFlags: [
            "Repeated vomiting",
            "Trouble breathing",
            "Severe lethargy"
        ],
        vetRecommended: true,
        summary: "This may be a mild gastrointestinal issue, but worsening signs should be checked by a veterinarian."
    )
}
