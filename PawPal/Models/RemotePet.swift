import Foundation

struct RemotePet: Identifiable, Codable, Equatable, Hashable {
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
    var avatar_url: String?
    /// Cumulative boop count incremented by the virtual pet's tap-to-boop
    /// (CHANGELOG #38). Optional because older rows — and select statements
    /// that predate migration 013 — won't include the column. UI code
    /// should read via `pet.boop_count ?? 0`.
    var boop_count: Int?
    /// Persisted virtual-pet accessory ('none' / 'bow' / 'hat' /
    /// 'glasses'). Added in migration 014 so the dress-up state survives
    /// between sessions. Nil is treated as 'none' — if the column is
    /// missing (pre-migration clients) the renderer falls back cleanly.
    var accessory: String?

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
