import Foundation

struct RemotePet: Identifiable, Codable, Equatable {
    let id: UUID
    let owner_user_id: UUID
    var name: String
    var species: String?
    var breed: String?
    var age: String?
    var weight: String?
    var notes: String?
    let created_at: Date
}
