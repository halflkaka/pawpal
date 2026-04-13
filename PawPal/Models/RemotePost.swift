import Foundation

struct RemotePost: Identifiable, Codable, Hashable {
    static func == (lhs: RemotePost, rhs: RemotePost) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    let id: UUID
    let owner_user_id: UUID          // matches posts table column name
    let pet_id: UUID
    let caption: String
    let mood: String?
    let created_at: Date

    let pets: RemotePet?
    let post_images: [RemotePostImage]
    var likes: [RemoteLike]          // likes table uses user_id (our own schema)
    var comments: [RemoteCommentStub]

    var pet: RemotePet? { pets }

    var sortedImages: [RemotePostImage] {
        post_images.sorted { $0.position < $1.position }
    }
    var imageURLs: [URL] {
        sortedImages.compactMap {
            guard let url = URL(string: $0.url), url.scheme != nil else { return nil }
            return url
        }
    }
    var likeCount: Int { likes.count }
    var commentCount: Int { comments.count }

    func isLiked(by userID: UUID) -> Bool {
        likes.contains { $0.user_id == userID }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, owner_user_id, pet_id, caption, mood, created_at, pets, post_images, likes, comments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(UUID.self,   forKey: .id)
        owner_user_id = try c.decode(UUID.self,   forKey: .owner_user_id)
        pet_id        = try c.decode(UUID.self,   forKey: .pet_id)
        caption       = try c.decode(String.self, forKey: .caption)
        mood          = try c.decodeIfPresent(String.self,        forKey: .mood)
        created_at    = try c.decode(Date.self,                   forKey: .created_at)
        pets          = try c.decodeIfPresent(RemotePet.self,     forKey: .pets)
        post_images   = (try? c.decode([RemotePostImage].self,    forKey: .post_images)) ?? []
        likes         = (try? c.decode([RemoteLike].self,         forKey: .likes))       ?? []
        comments      = (try? c.decode([RemoteCommentStub].self,  forKey: .comments))    ?? []
    }

    init(
        id: UUID, owner_user_id: UUID, pet_id: UUID,
        caption: String, mood: String?, created_at: Date,
        pets: RemotePet?, post_images: [RemotePostImage],
        likes: [RemoteLike] = [], comments: [RemoteCommentStub] = []
    ) {
        self.id = id; self.owner_user_id = owner_user_id; self.pet_id = pet_id
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

    init(user_id: UUID) {
        self.user_id = user_id
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let userIDString = try? container.decode(String.self),
           let userID = UUID(uuidString: userIDString) {
            self.user_id = userID
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let userID = try? container.decode(UUID.self, forKey: .user_id) {
            self.user_id = userID
            return
        }
        let userIDString = try container.decode(String.self, forKey: .user_id)
        guard let userID = UUID(uuidString: userIDString) else {
            throw DecodingError.dataCorruptedError(forKey: .user_id, in: container, debugDescription: "Invalid user_id UUID string")
        }
        self.user_id = userID
    }

    private enum CodingKeys: String, CodingKey {
        case user_id
    }
}

struct RemoteCommentStub: Codable {
    let id: UUID
}
