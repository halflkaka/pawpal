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

    // Full join used when loading the feed (includes engagement counts)
    private static let joinSelect = "*, pets(*), post_images(id, url, position), likes(user_id), comments(id)"
    // Lean join used immediately after insert — no likes/comments yet on a new post,
    // and the tables may not exist until the user runs the engagement SQL migration.
    private static let createSelect = "*, pets(*), post_images(id, url, position)"

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
            errorMessage = "动态加载失败，下拉可重试。"
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
            // Generate the post ID client-side so we can use it for image
            // paths without needing a select-back after the insert.
            let postID = UUID()
            let trimmedMood = mood.trimmingCharacters(in: .whitespacesAndNewlines)

            struct NewPost: Encodable {
                let id: UUID
                let user_id: UUID
                let pet_id: UUID
                let caption: String
                let mood: String?
            }

            // Bare insert — no .select() so no FK join can break it
            try await client
                .from("posts")
                .insert(NewPost(
                    id: postID,
                    user_id: userID,
                    pet_id: petID,
                    caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
                    mood: trimmedMood.isEmpty ? nil : trimmedMood
                ))
                .execute()

            // Upload images (non-fatal if storage isn't configured yet)
            if !imageData.isEmpty {
                var insertPayloads: [[String: String]] = []
                for (index, data) in imageData.enumerated() {
                    let jpeg = compressToJPEG(data)
                    let path = "\(userID.uuidString)/\(postID.uuidString)/\(index).jpg"
                    do {
                        _ = try await client.storage
                            .from(storageBucket)
                            .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: true))
                        let publicURL = try client.storage.from(storageBucket).getPublicURL(path: path)
                        insertPayloads.append([
                            "post_id": postID.uuidString,
                            "url": publicURL.absoluteString,
                            "position": "\(index)"
                        ])
                    } catch {
                        print("[PostsService] 图片上传失败 index=\(index): \(error)")
                    }
                }
                if !insertPayloads.isEmpty {
                    try await client.from("post_images").insert(insertPayloads).execute()
                }
            }

            await loadFeed()
            return true
        } catch {
            // Surface the real error so it's visible during development
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            print("[PostsService] createPost 失败: \(msg)")
            errorMessage = msg
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

    // MARK: - Likes (optimistic)

    func toggleLike(postID: UUID, userID: UUID) async {
        guard let index = feedPosts.firstIndex(where: { $0.id == postID }) else { return }
        let original = feedPosts[index]
        let alreadyLiked = original.isLiked(by: userID)

        // Optimistic update — modify locally before the network call
        var updated = original
        if alreadyLiked {
            updated.likes = original.likes.filter { $0.user_id != userID }
        } else {
            updated.likes = original.likes + [RemoteLike(user_id: userID)]
        }
        feedPosts[index] = updated

        // Sync with server
        do {
            if alreadyLiked {
                try await client
                    .from("likes")
                    .delete()
                    .eq("post_id", value: postID.uuidString)
                    .eq("user_id", value: userID.uuidString)
                    .execute()
            } else {
                try await client
                    .from("likes")
                    .insert(["post_id": postID.uuidString, "user_id": userID.uuidString])
                    .execute()
            }
        } catch {
            // Roll back on failure
            feedPosts[index] = original
        }
    }

    // MARK: - Comments

    func loadComments(for postID: UUID) async -> [RemoteComment] {
        do {
            return try await client
                .from("comments")
                .select("*, profiles!user_id(username, display_name)")
                .eq("post_id", value: postID.uuidString)
                .order("created_at", ascending: true)
                .execute()
                .value
        } catch {
            return []
        }
    }

    func addComment(postID: UUID, userID: UUID, content: String) async -> RemoteComment? {
        struct NewComment: Encodable {
            let post_id: UUID
            let user_id: UUID
            let content: String
        }
        do {
            let comment: RemoteComment = try await client
                .from("comments")
                .insert(NewComment(post_id: postID, user_id: userID, content: content))
                .select("*, profiles!user_id(username, display_name)")
                .single()
                .execute()
                .value

            // Bump local comment stub count
            if let index = feedPosts.firstIndex(where: { $0.id == postID }) {
                var updated = feedPosts[index]
                updated.comments.append(RemoteCommentStub(id: comment.id))
                feedPosts[index] = updated
            }
            return comment
        } catch {
            return nil
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
