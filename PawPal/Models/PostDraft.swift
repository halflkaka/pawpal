import Foundation

struct PostDraft: Identifiable {
    let id = UUID()
    var petID: UUID?
    var caption: String = ""
}
