import Foundation

struct RemotePet: Identifiable, Codable, Equatable {
    let id: UUID
    let owner_user_id: UUID
    var name: String
    var species: String?
    var breed: String?
    var sex: String?
    var age_text: String?
    var weight: String?
    var home_city: String?
    var bio: String?

    var hometown: String? {
        get { home_city }
        set { home_city = newValue }
    }
    let created_at: Date

    var age: String? {
        get { age_text }
        set { age_text = newValue }
    }
}
