import Foundation
import Testing
@testable import PetHealth

struct PawPalTests {

    @Test func remotePostImageSortsByPosition() {
        let images = [
            RemotePostImage(id: UUID(), url: "https://example.com/2.jpg", position: 2),
            RemotePostImage(id: UUID(), url: "https://example.com/0.jpg", position: 0),
            RemotePostImage(id: UUID(), url: "https://example.com/1.jpg", position: 1)
        ]
        let post = makePost(images: images)
        let sorted = post.sortedImages
        #expect(sorted[0].position == 0)
        #expect(sorted[1].position == 1)
        #expect(sorted[2].position == 2)
    }

    @Test func remotePostImageURLsFilterInvalid() {
        let images = [
            RemotePostImage(id: UUID(), url: "https://cdn.example.com/img.jpg", position: 0),
            RemotePostImage(id: UUID(), url: "not-a-url", position: 1)
        ]
        let post = makePost(images: images)
        #expect(post.imageURLs.count == 1)
        #expect(post.imageURLs.first?.absoluteString == "https://cdn.example.com/img.jpg")
    }

    @Test func likeCount() {
        let uid1 = UUID()
        let uid2 = UUID()
        var post = makePost()
        #expect(post.likeCount == 0)
        #expect(!post.isLiked(by: uid1))

        post.likes = [RemoteLike(user_id: uid1), RemoteLike(user_id: uid2)]
        #expect(post.likeCount == 2)
        #expect(post.isLiked(by: uid1))
        #expect(!post.isLiked(by: UUID()))
    }

    @Test func commentCount() {
        var post = makePost()
        #expect(post.commentCount == 0)

        post.comments = [RemoteCommentStub(id: UUID()), RemoteCommentStub(id: UUID())]
        #expect(post.commentCount == 2)
    }

    @Test func remotePetAgeAccessor() {
        var pet = RemotePet(id: UUID(), owner_user_id: UUID(), name: "Mochi", created_at: .now)
        pet.age = "3 岁"
        #expect(pet.age_text == "3 岁")
        #expect(pet.age == "3 岁")
    }

    // MARK: - Helper

    private func makePost(images: [RemotePostImage] = []) -> RemotePost {
        RemotePost(
            id: UUID(), owner_user_id: UUID(), pet_id: UUID(),
            caption: "Test", mood: nil, created_at: .now,
            pets: nil, post_images: images,
            likes: [], comments: []
        )
    }
}
