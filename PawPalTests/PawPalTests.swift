import Foundation
import SwiftData
import Testing
@testable import PetHealth

struct PawPalTests {
    @Test func storedPostCanBeSavedAndFetched() throws {
        let container = try ModelContainer(
            for: StoredPost.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let post = StoredPost(
            petID: UUID(),
            petName: "Mochi",
            caption: "Napping in the sun ☀️",
            mood: "Cozy"
        )
        context.insert(post)
        try context.save()

        let descriptor = FetchDescriptor<StoredPost>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let posts = try context.fetch(descriptor)

        #expect(posts.count == 1)
        #expect(posts.first?.petName == "Mochi")
        #expect(posts.first?.caption == "Napping in the sun ☀️")
    }

    @Test func storedPostImageEncodingRoundTrips() {
        let imageData = Data([0xFF, 0xD8, 0xFF]) // fake JPEG header
        let encoded = StoredPost.encodeImageDataList([imageData])
        let decoded = StoredPost.decodeImageDataList(encoded)

        #expect(decoded.count == 1)
        #expect(decoded.first == imageData)
    }
}
