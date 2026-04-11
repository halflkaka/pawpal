import Foundation

struct RemotePost: Identifiable, Codable {
    let id: UUID
    let user_id: UUID
    let pet_id: UUID
    let caption: String
    let mood: String?
    let created_at: Date

    let pets: RemotePet?
    let post_images: [RemotePostImage]
    var likes: [RemoteLike]
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

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, user_id, pet_id, caption, mood, created_at, pets, post_images, likes, comments
    }

    // Custom decoder: likes and comments default to [] if the tables don't
    // exist yet or the join returns nothing — prevents the whole query from
    // failing just because the engagement tables haven't been created.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self,   forKey: .id)
        user_id    = try c.decode(UUID.self,   forKey: .user_id)
        pet_id     = try c.decode(UUID.self,   forKey: .pet_id)
        caption    = try c.decode(String.self, forKey: .caption)
        mood       = try c.decodeIfPresent(String.self,           forKey: .mood)
        created_at = try c.decode(Date.self,                      forKey: .created_at)
        pets       = try c.decodeIfPresent(RemotePet.self,        forKey: .pets)
        post_images = (try? c.decode([RemotePostImage].self,      forKey: .post_images)) ?? []
        likes       = (try? c.decode([RemoteLike].self,           forKey: .likes))       ?? []
        comments    = (try? c.decode([RemoteCommentStub].self,    forKey: .comments))    ?? []
    }

    // Memberwise init used in tests and optimistic-update code
    init(
        id: UUID, user_id: UUID, pet_id: UUID,
        caption: String, mood: String?, created_at: Date,
        pets: RemotePet?, post_images: [RemotePostImage],
        likes: [RemoteLike] = [], comments: [RemoteCommentStub] = []
    ) {
        self.id = id; self.user_id = user_id; self.pet_id = pet_id
        self.caption = caption; self.mood = mood; self.created_at = created_at
        self.pets = pets; self.post_images = post_images
        self.likes = likes; self.comments = comments
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

struct RemoteCommentStub: Codable {
    let id: UUID
}
