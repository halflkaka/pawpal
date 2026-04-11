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
        let post = RemotePost(
            id: UUID(),
            user_id: UUID(),
            pet_id: UUID(),
            caption: "Test",
            mood: nil,
            created_at: .now,
            pets: nil,
            post_images: images
        )
        let sorted = post.sortedImages
        #expect(sorted[0].position == 0)
        #expect(sorted[1].position == 1)
        #expect(sorted[2].position == 2)
    }

    @Test func remotePostImageURLsAreValid() {
        let images = [
            RemotePostImage(id: UUID(), url: "https://cdn.example.com/img.jpg", position: 0),
            RemotePostImage(id: UUID(), url: "not-a-url", position: 1)
        ]
        let post = RemotePost(
            id: UUID(),
            user_id: UUID(),
            pet_id: UUID(),
            caption: "Photo test",
            mood: "Happy",
            created_at: .now,
            pets: nil,
            post_images: images
        )
        // Only the valid URL should be returned
        #expect(post.imageURLs.count == 1)
        #expect(post.imageURLs.first?.absoluteString == "https://cdn.example.com/img.jpg")
    }

    @Test func remotePetAgeAccessor() {
        var pet = RemotePet(
            id: UUID(),
            owner_user_id: UUID(),
            name: "Mochi",
            created_at: .now
        )
        pet.age = "3 years"
        #expect(pet.age_text == "3 years")
        #expect(pet.age == "3 years")
    }
}
