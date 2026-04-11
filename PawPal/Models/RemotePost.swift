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

    var pet: RemotePet? { pets }

    var sortedImages: [RemotePostImage] {
        post_images.sorted { $0.position < $1.position }
    }

    var imageURLs: [URL] {
        sortedImages.compactMap { URL(string: $0.url) }
    }
}

struct RemotePostImage: Codable {
    let id: UUID
    let url: String
    let position: Int
}
