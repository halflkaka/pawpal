import Foundation
import UIKit
import Supabase

@MainActor
final class PostsService: ObservableObject {
    @Published var feedPosts: [RemotePost] = []
    @Published var userPosts: [RemotePost] = []
    @Published var isLoadingFeed = false
    @Published var isPosting = false
    @Published var errorMessage: String?

    private let client: SupabaseClient
    private let storageBucket = "post-images"

    private static let joinSelect = "*, pets(*), post_images(id, url, position)"

    init() {
        guard let url = URL(string: SupabaseConfig.urlString) else {
            fatalError("Invalid Supabase URL")
        }
        client = SupabaseClient(supabaseURL: url, supabaseKey: SupabaseConfig.anonKey)
    }

    // MARK: - Load Feed

    func loadFeed() async {
        isLoadingFeed = true
        errorMessage = nil
        defer { isLoadingFeed = false }

        do {
            let posts: [RemotePost] = try await client
                .from("posts")
                .select(Self.joinSelect)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value
            feedPosts = posts
        } catch {
            errorMessage = "Couldn't load the feed. Pull to refresh."
        }
    }

    // MARK: - Load User Posts (for profile grid)

    func loadUserPosts(for userID: UUID) async {
        do {
            let posts: [RemotePost] = try await client
                .from("posts")
                .select(Self.joinSelect)
                .eq("user_id", value: userID.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
            userPosts = posts
        } catch {
            userPosts = []
        }
    }

    // MARK: - Create Post

    func createPost(
        userID: UUID,
        petID: UUID,
        caption: String,
        mood: String,
        imageData: [Data]
    ) async -> Bool {
        isPosting = true
        errorMessage = nil
        defer { isPosting = false }

        do {
            // 1. Insert the post row
            struct NewPost: Encodable {
                let user_id: UUID
                let pet_id: UUID
                let caption: String
                let mood: String?
            }

            let trimmedMood = mood.trimmingCharacters(in: .whitespacesAndNewlines)
            let post: RemotePost = try await client
                .from("posts")
                .insert(NewPost(
                    user_id: userID,
                    pet_id: petID,
                    caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
                    mood: trimmedMood.isEmpty ? nil : trimmedMood
                ))
                .select(Self.joinSelect)
                .single()
                .execute()
                .value

            // 2. Upload images to Supabase Storage and collect URLs
            if !imageData.isEmpty {
                var insertPayloads: [[String: String]] = []

                for (index, data) in imageData.enumerated() {
                    let jpeg = compressToJPEG(data)
                    let path = "\(userID.uuidString)/\(post.id.uuidString)/\(index).jpg"

                    do {
                        _ = try await client.storage
                            .from(storageBucket)
                            .upload(
                                path,
                                data: jpeg,
                                options: FileOptions(contentType: "image/jpeg", upsert: true)
                            )

                        let publicURL = try client.storage
                            .from(storageBucket)
                            .getPublicURL(path: path)

                        insertPayloads.append([
                            "post_id": post.id.uuidString,
                            "url": publicURL.absoluteString,
                            "position": "\(index)"
                        ])
                    } catch {
                        // Non-fatal: continue with other images
                        print("[PostsService] Image upload failed at index \(index): \(error)")
                    }
                }

                if !insertPayloads.isEmpty {
                    try await client
                        .from("post_images")
                        .insert(insertPayloads)
                        .execute()
                }
            }

            // 3. Reload the feed so the new post appears with images
            await loadFeed()
            return true

        } catch {
            errorMessage = "Couldn't post right now. Please try again."
            return false
        }
    }

    // MARK: - Delete Post

    func deletePost(_ postID: UUID, userID: UUID) async {
        do {
            try await client
                .from("posts")
                .delete()
                .eq("id", value: postID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()

            feedPosts.removeAll { $0.id == postID }
            userPosts.removeAll { $0.id == postID }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func compressToJPEG(_ data: Data, quality: CGFloat = 0.82) -> Data {
        guard let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: quality)
        else { return data }
        return jpeg
    }
}
