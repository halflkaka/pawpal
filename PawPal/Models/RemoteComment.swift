import Foundation

struct RemoteComment: Identifiable, Codable {
    let id: UUID
    let post_id: UUID
    let user_id: UUID
    let content: String
    let created_at: Date

    // Joined from profiles table via user_id
    let profiles: RemoteProfile?
    let username: String?
    let display_name: String?

    var authorName: String {
        if let dn = display_name?.trimmingCharacters(in: .whitespacesAndNewlines), !dn.isEmpty { return dn }
        if let dn = profiles?.display_name?.trimmingCharacters(in: .whitespacesAndNewlines), !dn.isEmpty { return dn }
        if let un = username?.trimmingCharacters(in: .whitespacesAndNewlines), !un.isEmpty { return "@\(un)" }
        if let un = profiles?.username?.trimmingCharacters(in: .whitespacesAndNewlines), !un.isEmpty { return "@\(un)" }
        return "用户"
    }

    enum CodingKeys: String, CodingKey {
        case id, post_id, user_id, content, created_at, profiles, username, display_name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        post_id = try c.decode(UUID.self, forKey: .post_id)
        user_id = try c.decode(UUID.self, forKey: .user_id)
        content = try c.decode(String.self, forKey: .content)
        created_at = try c.decode(Date.self, forKey: .created_at)
        profiles = try c.decodeIfPresent(RemoteProfile.self, forKey: .profiles)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        display_name = try c.decodeIfPresent(String.self, forKey: .display_name)
    }

    init(id: UUID, post_id: UUID, user_id: UUID, content: String, created_at: Date, profiles: RemoteProfile?, username: String? = nil, display_name: String? = nil) {
        self.id = id
        self.post_id = post_id
        self.user_id = user_id
        self.content = content
        self.created_at = created_at
        self.profiles = profiles
        self.username = username
        self.display_name = display_name
    }
}
