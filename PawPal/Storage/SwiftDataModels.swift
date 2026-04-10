import Foundation
import SwiftData

@Model
final class StoredPost {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var petID: UUID?
    var petName: String
    var caption: String
    var mood: String
    var imageDataListJSON: String

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        petID: UUID? = nil,
        petName: String = "",
        caption: String,
        mood: String,
        imageDataListJSON: String = "[]"
    ) {
        self.id = id
        self.createdAt = createdAt
        self.petID = petID
        self.petName = petName
        self.caption = caption
        self.mood = mood
        self.imageDataListJSON = imageDataListJSON
    }

    var imageDataList: [Data] {
        Self.decodeImageDataList(imageDataListJSON)
    }

    static func encodeImageDataList(_ values: [Data]) -> String {
        let base64 = values.map { $0.base64EncodedString() }
        let data = (try? JSONEncoder().encode(base64)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    static func decodeImageDataList(_ value: String) -> [Data] {
        guard let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded.compactMap { Data(base64Encoded: $0) }
    }
}
