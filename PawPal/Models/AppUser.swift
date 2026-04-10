import Foundation

struct AppUser: Identifiable, Equatable {
    let id: UUID
    var email: String?
    var displayName: String?
}
