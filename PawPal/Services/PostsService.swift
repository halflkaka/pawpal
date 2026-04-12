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

    // Fallback chain — tried in order until one succeeds.
    // Splitting likes/comments into separate levels means a missing comments
    // table won't also wipe the likes data.
    private static let selectLevels: [String] = [
        "*, pets(*), post_images(id, url, position), likes(user_id), comments(id)", // all tables
        "*, pets(*), post_images(id, url, position), likes(user_id)",               // likes, no comments
        "*, pets(*), post_images(id, url, position)",                               // images, no engagement
        "*, pets(*)"                                                                 // bare minimum
    ]
    private static let commentOnlySelect = "id, comments(id)"

    init() {
        client = SupabaseConfig.client
    }

    // MARK: - Load Feed

    func loadFeed(followingIDs: [UUID]? = nil) async {
        isLoadingFeed = true
        errorMessage = nil
        defer { isLoadingFeed = false }

        // Snapshot current in-memory likes so we can restore optimistic state
        // for posts where the server returns an empty likes array (e.g. when
        // the likes table exists but the join level doesn't include it).
        let previousLikes: [UUID: [RemoteLike]] = Dictionary(
            uniqueKeysWithValues: feedPosts.map { ($0.id, $0.likes) }
        )

        for select in Self.selectLevels {
            do {
                // Filters (.in) must come before transforms (.order/.limit),
                // so build the filter step first, then chain order+limit.
                var filter = client.from("posts").select(select)
                if let ids = followingIDs, !ids.isEmpty {
                    filter = filter.in("owner_user_id", values: ids.map(\.uuidString))
                }

                var posts: [RemotePost] = try await filter
                    .order("created_at", ascending: false)
                    .limit(50)
                    .execute()
                    .value

                // Restore optimistic like state: if the server returned an empty
                // likes array for a post we already have likes for locally,
                // keep the local version until the next full successful join.
                for i in posts.indices {
                    if posts[i].likes.isEmpty, let prev = previousLikes[posts[i].id], !prev.isEmpty {
                        posts[i].likes = prev
                    }
                }

                let mergedPosts = posts.map { post -> RemotePost in
                    var merged = post
                    if let previous = feedPosts.first(where: { $0.id == post.id }) {
                        if merged.likes.isEmpty, !previous.likes.isEmpty {
                            merged.likes = previous.likes
                        }
                        if merged.comments.isEmpty, let knownCount = commentCounts[post.id], knownCount > 0 {
                            merged.comments = Array(repeating: RemoteCommentStub(id: UUID()), count: knownCount)
                        }
                    }
                    return merged
                }

                feedPosts = mergedPosts
                commentCounts = Dictionary(uniqueKeysWithValues: mergedPosts.map { post in
                    (post.id, max(post.commentCount, commentCounts[post.id] ?? 0))
                })
                await refreshCommentCounts(for: mergedPosts.map(\.id))
                return
            } catch {
                print("[PostsService] loadFeed select='\(select)' 失败: \(error)")
            }
        }

        errorMessage = "动态加载失败，下拉可重试。"
    }

    // MARK: - Load User Posts (for profile grid)

    func loadUserPosts(for userID: UUID) async {
        for select in Self.selectLevels {
            do {
                let posts: [RemotePost] = try await client
                    .from("posts")
                    .select(select)
                    .eq("owner_user_id", value: userID.uuidString)
                    .order("created_at", ascending: false)
                    .execute()
                    .value
                let mergedPosts = posts.map { post -> RemotePost in
                    var merged = post
                    if let previous = userPosts.first(where: { $0.id == post.id }) {
                        if merged.likes.isEmpty, !previous.likes.isEmpty {
                            merged.likes = previous.likes
                        }
                        if merged.comments.isEmpty, let knownCount = commentCounts[post.id], knownCount > 0 {
                            merged.comments = Array(repeating: RemoteCommentStub(id: UUID()), count: knownCount)
                        }
                    }
                    return merged
                }

                userPosts = mergedPosts
                for post in mergedPosts {
                    commentCounts[post.id] = max(post.commentCount, commentCounts[post.id] ?? 0)
                }
                await refreshCommentCounts(for: mergedPosts.map(\.id))
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
        imageData: [Data],
        followingIDs: [UUID]? = nil
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

            await loadFeed(followingIDs: followingIDs)
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
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            print("[PostsService] toggleLike 失败: \(msg)")

            if !alreadyLiked && msg.lowercased().contains("duplicate") {
                // DB already has this like (local state was stale) — keep the
                // optimistic "liked" update, don't rollback.
                await syncLikes(for: postID)
                return
            }

            feedPosts[index] = original
            errorMessage = "点赞失败: \(msg)"
        }

        // Keep local state in sync after every successful toggle
        await syncLikes(for: postID)
    }

    /// Fetches the real like list for one post and updates feedPosts in place.
    private func syncLikes(for postID: UUID) async {
        struct LikeRow: Codable { let user_id: UUID }
        guard let likes = try? await client
            .from("likes")
            .select("user_id")
            .eq("post_id", value: postID.uuidString)
            .execute()
            .value as [LikeRow],
              let index = feedPosts.firstIndex(where: { $0.id == postID })
        else { return }
        feedPosts[index].likes = likes.map { RemoteLike(user_id: $0.user_id) }
    }

    // MARK: - Comments

    func loadComments(for postID: UUID) async -> [RemoteComment] {
        struct CommentRow: Codable {
            let id: UUID; let post_id: UUID; let user_id: UUID
            let content: String; let created_at: Date
        }
        struct ProfileRow: Codable {
            let id: UUID; let username: String?; let display_name: String?
        }

        // Step 1: load bare comment rows (no join dependency)
        let rows: [CommentRow]
        do {
            rows = try await client
                .from("comments")
                .select("id, post_id, user_id, content, created_at")
                .eq("post_id", value: postID.uuidString)
                .order("created_at", ascending: true)
                .execute()
                .value
        } catch {
            print("[PostsService] loadComments 失败: \(error)")
            return []
        }

        guard !rows.isEmpty else {
            commentCounts[postID] = 0
            syncCommentCount(postID: postID, count: 0)
            return []
        }

        // Step 2: batch-fetch profiles for all distinct authors
        let authorIDs = Array(Set(rows.map { $0.user_id.uuidString }))
        let profiles: [ProfileRow] = (try? await client
            .from("profiles")
            .select("id, username, display_name")
            .in("id", value: authorIDs)
            .execute()
            .value) ?? []
        let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

        // Step 3: assemble full comment objects
        let comments = rows.map { row -> RemoteComment in
            let p = profileMap[row.user_id]
            return RemoteComment(
                id: row.id, post_id: row.post_id, user_id: row.user_id,
                content: row.content, created_at: row.created_at, profiles: nil,
                username: p?.username, display_name: p?.display_name
            )
        }

        commentCounts[postID] = comments.count
        syncCommentCount(postID: postID, count: comments.count)
        return comments
    }

    func refreshCommentCount(for postID: UUID) async {
        await refreshCommentCounts(for: [postID])
    }

    func addComment(postID: UUID, userID: UUID, content: String) async -> RemoteComment? {
        struct NewComment: Encodable {
            let post_id: UUID; let user_id: UUID; let content: String
        }
        struct CommentRow: Codable {
            let id: UUID; let post_id: UUID; let user_id: UUID
            let content: String; let created_at: Date
        }
        struct ProfileRow: Codable {
            let username: String?; let display_name: String?
        }

        // INSERT exactly once — no selects here to avoid duplicate rows on retry
        let payload = NewComment(post_id: postID, user_id: userID, content: content)
        do {
            try await client.from("comments").insert(payload).execute()
        } catch {
            print("[PostsService] addComment insert 失败: \(error)")
            return nil
        }

        // Fetch the comment back — try with profiles join first, then without
        let row: CommentRow? = (
            try? await client.from("comments")
                .select("id, post_id, user_id, content, created_at")
                .eq("post_id", value: postID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value as [CommentRow]
        )?.first

        guard let row else {
            // Insert succeeded but read-back failed — still update counts
            bumpCommentStub(postID: postID, commentID: UUID())
            incrementCommentCount(postID: postID)
            return nil
        }

        // Fetch author name separately (avoids dependency on FK to profiles)
        let profileRow: ProfileRow? = try? await client
            .from("profiles")
            .select("username, display_name")
            .eq("id", value: userID.uuidString)
            .single()
            .execute()
            .value

        let comment = RemoteComment(
            id: row.id, post_id: row.post_id, user_id: row.user_id,
            content: row.content, created_at: row.created_at, profiles: nil,
            username: profileRow?.username, display_name: profileRow?.display_name
        )
        bumpCommentStub(postID: postID, commentID: comment.id)
        incrementCommentCount(postID: postID)
        return comment
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
        guard !postIDs.isEmpty else { return }

        struct CommentCountRow: Codable {
            let id: UUID
            let comments: [RemoteCommentStub]
        }

        do {
            let rows: [CommentCountRow] = try await client
                .from("posts")
                .select(Self.commentOnlySelect)
                .in("id", value: postIDs.map(\.uuidString))
                .execute()
                .value

            for row in rows {
                commentCounts[row.id] = row.comments.count
                syncCommentCount(postID: row.id, count: row.comments.count)
            }
        } catch {
            print("[PostsService] refreshCommentCounts 批量查询失败: \(error)")
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
