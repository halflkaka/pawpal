import Foundation

struct RemoteComment: Identifiable, Codable {
    let id: UUID
    let post_id: UUID
    let user_id: UUID
    let content: String
    let created_at: Date

    // Joined from profiles table via user_id
    let profiles: RemoteProfile?

    var authorName: String {
        if let dn = profiles?.display_name?.trimmingCharacters(in: .whitespacesAndNewlines), !dn.isEmpty { return dn }
        if let un = profiles?.username?.trimmingCharacters(in: .whitespacesAndNewlines), !un.isEmpty { return "@\(un)" }
        return "用户"
    }
}
