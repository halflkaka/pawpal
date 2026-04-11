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
    @Published private(set) var commentCounts: [UUID: Int] = [:]

    private let client: SupabaseClient
    private let storageBucket = "post-images"

    // Full join — posts + pet info + images + engagement
    private static let joinSelect    = "*, pets(*), post_images(id, url, position), likes(user_id), comments(id)"
    private static let commentOnlySelect = "id, comments(id)"
    // Mid join — posts + pet info + images (no likes/comments tables required)
    private static let createSelect  = "*, pets(*), post_images(id, url, position)"
    // Minimal join — posts + pet info only (no post_images table required)
    private static let minimalSelect = "*, pets(*)"

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

        // Try progressively leaner selects so the feed loads
        // regardless of which optional tables exist yet.
        let selects = [Self.joinSelect, Self.createSelect, Self.minimalSelect]
        var lastError: Error?

        for select in selects {
            do {
                let posts: [RemotePost] = try await client
                    .from("posts")
                    .select(select)
                    .order("created_at", ascending: false)
                    .limit(50)
                    .execute()
                    .value
                feedPosts = posts
                commentCounts = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0.commentCount) })
                await refreshCommentCounts(for: posts.map(\.id))
                return
            } catch {
                print("[PostsService] loadFeed select='\(select)' 失败: \(error)")
                lastError = error
            }
        }

        // All three selects failed — real problem (RLS, network, etc.)
        print("[PostsService] loadFeed 全部失败: \(lastError?.localizedDescription ?? "unknown")")
        errorMessage = "动态加载失败，下拉可重试。"
    }

    // MARK: - Load User Posts (for profile grid)

    func loadUserPosts(for userID: UUID) async {
        let selects = [Self.joinSelect, Self.createSelect, Self.minimalSelect]
        for select in selects {
            do {
                let posts: [RemotePost] = try await client
                    .from("posts")
                    .select(select)
                    .eq("owner_user_id", value: userID.uuidString)
                    .order("created_at", ascending: false)
                    .execute()
                    .value
                userPosts = posts
                for post in posts {
                    commentCounts[post.id] = post.commentCount
                }
                await refreshCommentCounts(for: posts.map(\.id))
                return
            } catch {
                print("[PostsService] loadUserPosts select='\(select)' 失败: \(error)")
            }
        }
        userPosts = []
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
                let owner_user_id: UUID
                let pet_id: UUID
                let caption: String
                let mood: String?
            }

            // Bare insert — no .select() so no FK join can break it
            try await client
                .from("posts")
                .insert(NewPost(
                    id: postID,
                    owner_user_id: userID,
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
            errorMessage = nil   // post succeeded — don't show any feed-load noise
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
                .eq("owner_user_id", value: userID.uuidString)
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
        let selects = [
            "*, profiles!user_id(username, display_name)",
            "id, post_id, user_id, content, created_at"
        ]

        for select in selects {
            do {
                let comments: [RemoteComment] = try await client
                    .from("comments")
                    .select(select)
                    .eq("post_id", value: postID.uuidString)
                    .order("created_at", ascending: true)
                    .execute()
                    .value
                commentCounts[postID] = comments.count
                syncCommentCount(postID: postID, count: comments.count)
                return comments
            } catch {
                print("[PostsService] loadComments select='\(select)' 失败: \(error)")
            }
        }

        return []
    }

    func refreshCommentCount(for postID: UUID) async {
        await refreshCommentCounts(for: [postID])
    }

    func addComment(postID: UUID, userID: UUID, content: String) async -> RemoteComment? {
        struct NewComment: Encodable {
            let post_id: UUID
            let user_id: UUID
            let content: String
        }
        struct CommentRow: Codable {
            let id: UUID
            let post_id: UUID
            let user_id: UUID
            let content: String
            let created_at: Date
        }

        struct ProfileRow: Codable {
            let username: String?
            let display_name: String?
        }
        let payload = NewComment(post_id: postID, user_id: userID, content: content)

        // 1. Try full insert + select with profiles join
        if let comment = try? await client
            .from("comments")
            .insert(payload)
            .select("*, profiles!user_id(username, display_name)")
            .single()
            .execute()
            .value as RemoteComment {
            incrementCommentCount(postID: postID)
            bumpCommentStub(postID: postID, commentID: comment.id)
            return comment
        }

        // 2. Try insert + select without profiles, then fetch profile separately
        if let row = try? await client
            .from("comments")
            .insert(payload)
            .select("id, post_id, user_id, content, created_at")
            .single()
            .execute()
            .value as CommentRow {
            let profileRow: ProfileRow? = try? await client
                .from("profiles")
                .select("username, display_name")
                .eq("id", value: row.user_id.uuidString)
                .single()
                .execute()
                .value

            let comment = RemoteComment(
                id: row.id,
                post_id: row.post_id,
                user_id: row.user_id,
                content: row.content,
                created_at: row.created_at,
                profiles: nil,
                username: profileRow?.username,
                display_name: profileRow?.display_name
            )
            incrementCommentCount(postID: postID)
            bumpCommentStub(postID: postID, commentID: comment.id)
            return comment
        }

        // 3. Bare insert, then re-query the latest comment for this user/post
        do {
            try await client.from("comments").insert(payload).execute()

            if let comments = try? await client
                .from("comments")
                .select("id, post_id, user_id, content, created_at")
                .eq("post_id", value: postID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value as [CommentRow],
               let row = comments.first {
                let profileRow: ProfileRow? = try? await client
                    .from("profiles")
                    .select("username, display_name")
                    .eq("id", value: row.user_id.uuidString)
                    .single()
                    .execute()
                    .value

                let comment = RemoteComment(
                    id: row.id,
                    post_id: row.post_id,
                    user_id: row.user_id,
                    content: row.content,
                    created_at: row.created_at,
                    profiles: nil,
                    username: profileRow?.username,
                    display_name: profileRow?.display_name
                )
                incrementCommentCount(postID: postID)
                bumpCommentStub(postID: postID, commentID: comment.id)
                return comment
            }

            print("[PostsService] addComment 插入成功，但回读失败")
            return nil
        } catch {
            print("[PostsService] addComment 全部失败: \(error)")
            return nil
        }
    }

    private func bumpCommentStub(postID: UUID, commentID: UUID) {
        if let index = feedPosts.firstIndex(where: { $0.id == postID }), !feedPosts[index].comments.contains(where: { $0.id == commentID }) {
            var updated = feedPosts[index]
            updated.comments.append(RemoteCommentStub(id: commentID))
            feedPosts[index] = updated
        }
        if let index = userPosts.firstIndex(where: { $0.id == postID }), !userPosts[index].comments.contains(where: { $0.id == commentID }) {
            var updated = userPosts[index]
            updated.comments.append(RemoteCommentStub(id: commentID))
            userPosts[index] = updated
        }
    }

    private func incrementCommentCount(postID: UUID) {
        let nextCount = (commentCounts[postID] ?? currentCommentCount(for: postID)) + 1
        commentCounts[postID] = nextCount
        syncCommentCount(postID: postID, count: nextCount)
    }

    private func syncCommentCount(postID: UUID, count: Int) {
        if let index = feedPosts.firstIndex(where: { $0.id == postID }) {
            var updated = feedPosts[index]
            updated.comments = Array(updated.comments.prefix(count))
            while updated.comments.count < count {
                updated.comments.append(RemoteCommentStub(id: UUID()))
            }
            feedPosts[index] = updated
        }

        if let index = userPosts.firstIndex(where: { $0.id == postID }) {
            var updated = userPosts[index]
            updated.comments = Array(updated.comments.prefix(count))
            while updated.comments.count < count {
                updated.comments.append(RemoteCommentStub(id: UUID()))
            }
            userPosts[index] = updated
        }
    }

    func commentCount(for postID: UUID) -> Int {
        commentCounts[postID] ?? currentCommentCount(for: postID)
    }

    private func currentCommentCount(for postID: UUID) -> Int {
        feedPosts.first(where: { $0.id == postID })?.comments.count
            ?? userPosts.first(where: { $0.id == postID })?.comments.count
            ?? 0
    }

    private func refreshCommentCounts(for postIDs: [UUID]) async {
        for postID in postIDs {
            do {
                struct CommentCountRow: Codable {
                    let id: UUID
                    let comments: [RemoteCommentStub]
                }

                let row: CommentCountRow = try await client
                    .from("posts")
                    .select(Self.commentOnlySelect)
                    .eq("id", value: postID.uuidString)
                    .single()
                    .execute()
                    .value

                commentCounts[postID] = row.comments.count
                syncCommentCount(postID: postID, count: row.comments.count)
            } catch {
                print("[PostsService] refreshCommentCounts postID=\(postID) 失败: \(error)")
            }
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
