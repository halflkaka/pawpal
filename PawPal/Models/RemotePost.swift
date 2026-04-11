import Foundation

struct RemotePost: Identifiable, Codable {
    let id: UUID
    let user_id: UUID
    let pet_id: UUID
    let caption: String
    let mood: String?
    let created_at: Date

    // Joined from pets table (many-to-one via pet_id)
    let pets: RemotePet?
    // Joined from post_images table (one-to-many via post_id)
    let post_images: [RemotePostImage]
    // Joined from likes table — user_id only, for counting and liked-by-me checks
    var likes: [RemoteLike]
    // Joined from comments table — id only, for counting
    var comments: [RemoteCommentStub]

    var pet: RemotePet? { pets }

    var sortedImages: [RemotePostImage] {
        post_images.sorted { $0.position < $1.position }
    }

    var imageURLs: [URL] {
        sortedImages.compactMap { URL(string: $0.url) }
    }

    var likeCount: Int { likes.count }
    var commentCount: Int { comments.count }

    func isLiked(by userID: UUID) -> Bool {
        likes.contains { $0.user_id == userID }
    }
}

struct RemotePostImage: Codable {
    let id: UUID
    let url: String
    let position: Int
}

struct RemoteLike: Codable {
    let user_id: UUID
}

// Minimal stub used in the feed query — just enough to count comments
struct RemoteCommentStub: Codable {
    let id: UUID
}
