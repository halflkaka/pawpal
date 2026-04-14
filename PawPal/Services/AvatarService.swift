import Foundation
import UIKit
import Supabase

struct AvatarService {
    private let client = SupabaseConfig.client
    // Reuse the existing post-images bucket — avatars go under
    // {ownerID}/pet-avatar/{petID}.jpg, which keeps them within the
    // user's own folder prefix (satisfying existing RLS policies).
    private let bucket = "post-images"

    func uploadUserAvatar(data: Data, userID: UUID) async throws -> String {
        let path = "\(userID.uuidString)/user-avatar/\(userID.uuidString).jpg"
        let jpeg = compress(data)
        _ = try await client.storage
            .from(bucket)
            .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: true))
        return try client.storage.from(bucket).getPublicURL(path: path).absoluteString
    }

    func uploadPetAvatar(data: Data, ownerID: UUID, petID: UUID) async throws -> String {
        let path = "\(ownerID.uuidString)/pet-avatar/\(petID.uuidString).jpg"
        let jpeg = compress(data)
        _ = try await client.storage
            .from(bucket)
            .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: true))
        return try client.storage.from(bucket).getPublicURL(path: path).absoluteString
    }

    private func compress(_ data: Data) -> Data {
        guard let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.82) else { return data }
        // Resize to max 512px on the long edge before compressing
        let size = image.size
        let maxEdge: CGFloat = 512
        guard max(size.width, size.height) > maxEdge else { return jpeg }
        let scale = maxEdge / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: 0.82) ?? jpeg
    }
}
