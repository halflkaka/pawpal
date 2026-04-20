import Foundation
import UIKit
import Supabase

@MainActor
final class PostsService: ObservableObject {
    @Published var feedPosts: [RemotePost] = []
    @Published var userPosts: [RemotePost] = []
    @Published var petPosts: [RemotePost] = []
    @Published var isLoadingFeed = false
    @Published var isLoadingPetPosts = false
    @Published var isPosting = false
    @Published var errorMessage: String?
    @Published private(set) var commentCounts: [UUID: Int] = [:]
    /// Last 2 comments per post — displayed inline on the feed card (Instagram style).
    @Published private(set) var commentPreviews: [UUID: [RemoteComment]] = [:]

    private let client: SupabaseClient
    private let storageBucket = "post-images"

    /// Token for the `petDidUpdate` NotificationCenter subscription —
    /// held so we can detach in `deinit`. Without this, every instance
    /// of `PostsService` that's been deallocated would still get woken
    /// up on every pet edit and the weak-self dance would quietly
    /// no-op — correct, but wasteful once enough views have churned.
    private var petUpdateObserver: NSObjectProtocol?

    // Fallback chain — tried in order until one succeeds.
    // Splitting likes/comments into separate levels means a missing comments
    // table won't also wipe the likes data. The owner profile is joined in
    // every level except the final bare-minimum fallback so feed cards can
    // show the real owner handle in the inline-bold caption prefix; the
    // minimal level still works even if the profiles FK name is mis-hinted
    // in some edge-case schema state.
    private static let selectLevels: [String] = [
        "*, pets(*), profiles!owner_user_id(*), post_images(id, url, position), likes(user_id), comments(id)", // all tables
        "*, pets(*), profiles!owner_user_id(*), post_images(id, url, position), likes(user_id)",               // likes, no comments
        "*, pets(*), profiles!owner_user_id(*), post_images(id, url, position)",                               // images, no engagement
        "*, pets(*)"                                                                                            // bare minimum
    ]
    private static let commentOnlySelect = "id, comments(id)"

    private struct LikeRow: Codable {
        let post_id: UUID
        let user_id: UUID
    }

    init() {
        client = SupabaseConfig.client

        // Subscribe to pet mutations so cached post rows pick up new
        // avatars / accessories without a hard refresh. See the
        // Notification.Name extension in PetsService.swift for the
        // cross-service rationale. We bounce onto the MainActor via
        // Task because MainActor-isolated methods can't be called
        // directly from the NotificationCenter callback (which may
        // arrive on an arbitrary thread).
        petUpdateObserver = NotificationCenter.default.addObserver(
            forName: .petDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self, let pet = note.userInfo?["pet"] as? RemotePet else { return }
            Task { @MainActor in self.patchPet(pet) }
        }
    }

    deinit {
        if let petUpdateObserver {
            NotificationCenter.default.removeObserver(petUpdateObserver)
        }
    }

    // MARK: - Load Feed

    func loadFeed(followingIDs: [UUID]? = nil, currentUserID: UUID? = nil) async {
        isLoadingFeed = true
        errorMessage = nil
        defer { isLoadingFeed = false }

        // Prefer the caller-provided ID so we never block on auth.session
        // (which can hang if a token refresh is in flight).
        let resolvedCurrentUserID: UUID?
        if let currentUserID {
            resolvedCurrentUserID = currentUserID
        } else {
            resolvedCurrentUserID = try? await client.auth.session.user.id
        }

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

                // Restore optimistic like state only for the currently signed-in
                // user. This avoids cross-run stale like badges while still
                // protecting against partial join results.
                for i in posts.indices {
                    if posts[i].likes.isEmpty,
                       let resolvedCurrentUserID,
                       let prev = previousLikes[posts[i].id],
                       prev.contains(where: { $0.user_id == resolvedCurrentUserID }) {
                        posts[i].likes = [RemoteLike(user_id: resolvedCurrentUserID)]
                    }
                }

                let mergedPosts = posts.map { post -> RemotePost in
                    var merged = post
                    if let previous = feedPosts.first(where: { $0.id == post.id }) {
                        if merged.likes.isEmpty,
                           let resolvedCurrentUserID,
                           previous.likes.contains(where: { $0.user_id == resolvedCurrentUserID }) {
                            merged.likes = [RemoteLike(user_id: resolvedCurrentUserID)]
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

                // Secondary engagement data loads in the background so
                // .refreshable can dismiss immediately after posts arrive.
                let postIDs = mergedPosts.map(\.id)
                Task { [weak self] in
                    guard let self else { return }
                    await self.refreshLikes(for: postIDs)
                    await self.refreshCommentCounts(for: postIDs)
                    await self.loadCommentPreviews(for: postIDs)
                }
                return
            } catch {
                print("[PostsService] loadFeed select='\(select)' 失败: \(error)")
            }
        }

        errorMessage = "动态加载失败，下拉可重试。"
    }

    // MARK: - Load User Posts (for profile grid)

    func loadUserPosts(for userID: UUID) async {
        let currentUserID = try? await client.auth.session.user.id

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
                        if merged.likes.isEmpty,
                           let currentUserID,
                           previous.likes.contains(where: { $0.user_id == currentUserID }) {
                            merged.likes = [RemoteLike(user_id: currentUserID)]
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
                let postIDs = mergedPosts.map(\.id)
                Task { [weak self] in
                    guard let self else { return }
                    await self.refreshLikes(for: postIDs)
                    await self.refreshCommentCounts(for: postIDs)
                }
                return
            } catch {
                print("[PostsService] loadUserPosts select='\(select)' 失败: \(error)")
            }
        }
        userPosts = []
    }

    // MARK: - Memory loop (milestones MVP)

    /// Posts authored by the user whose `created_at` month-day matches
    /// today's local month-day and whose year is strictly earlier. Used
    /// by the FeedView memory card.
    ///
    /// Implementation: fetch the user's most recent posts (capped at 200)
    /// via the same multi-level select fallback we use for `loadFeed`,
    /// then filter client-side for month-day match where
    /// `calendarYear(created_at) < calendarYear(now)`. Acceptable at the
    /// early-product scale (<200 lifetime posts per user). Promote to a
    /// server-side RPC / generated column when scale demands.
    ///
    /// TODO(milestones-mvp): once a user exceeds ~200 lifetime posts,
    /// swap this to a server-side filter (PostgREST `or=` with
    /// `extract(month from created_at)` via an RPC, or a generated
    /// `month_day text` column).
    func loadMemoryPosts(forUser userID: UUID, now: Date = Date()) async -> [RemotePost] {
        let cal = Calendar.current
        let todayComps = cal.dateComponents([.year, .month, .day], from: now)
        guard let todayMonth = todayComps.month,
              let todayDay = todayComps.day,
              let todayYear = todayComps.year else { return [] }

        for select in Self.selectLevels {
            do {
                let posts: [RemotePost] = try await client
                    .from("posts")
                    .select(select)
                    .eq("owner_user_id", value: userID.uuidString)
                    .order("created_at", ascending: false)
                    .limit(200)
                    .execute()
                    .value

                return posts.filter { post in
                    let c = cal.dateComponents([.year, .month, .day], from: post.created_at)
                    guard let m = c.month, let d = c.day, let y = c.year else { return false }
                    return m == todayMonth && d == todayDay && y < todayYear
                }
            } catch {
                print("[PostsService] loadMemoryPosts select='\(select)' 失败: \(error)")
            }
        }
        return []
    }

    // MARK: - Load Pet Posts (for pet profile page)

    func loadPetPosts(for petID: UUID) async {
        isLoadingPetPosts = true
        errorMessage = nil
        defer { isLoadingPetPosts = false }

        let currentUserID = try? await client.auth.session.user.id

        for select in Self.selectLevels {
            do {
                var posts: [RemotePost] = try await client
                    .from("posts")
                    .select(select)
                    .eq("pet_id", value: petID.uuidString)
                    .order("created_at", ascending: false)
                    .execute()
                    .value

                if let currentUserID {
                    for i in posts.indices {
                        if posts[i].likes.isEmpty,
                           let prev = petPosts.first(where: { $0.id == posts[i].id }),
                           prev.likes.contains(where: { $0.user_id == currentUserID }) {
                            posts[i].likes = [RemoteLike(user_id: currentUserID)]
                        }
                    }
                }

                petPosts = posts
                for post in posts {
                    commentCounts[post.id] = max(post.commentCount, commentCounts[post.id] ?? 0)
                }
                let postIDs = posts.map(\.id)
                Task { [weak self] in
                    guard let self else { return }
                    await self.refreshLikes(for: postIDs)
                    await self.refreshCommentCounts(for: postIDs)
                }
                return
            } catch {
                print("[PostsService] loadPetPosts select='\(select)' 失败: \(error)")
            }
        }
        petPosts = []
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
            let postID = UUID()
            let trimmedMood = mood.trimmingCharacters(in: .whitespacesAndNewlines)
            var uploadedPaths: [String] = []

            struct NewPost: Encodable {
                let id: UUID
                let owner_user_id: UUID
                let pet_id: UUID
                let caption: String
                let mood: String?
            }

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

            if !imageData.isEmpty {
                struct NewPostImage: Encodable {
                    let post_id: UUID
                    let url: String
                    let position: Int
                }

                do {
                    var insertPayloads: [NewPostImage] = []
                    for (index, data) in imageData.enumerated() {
                        let jpeg = compressToJPEG(data)
                        let path = "\(userID.uuidString)/\(postID.uuidString)/\(index).jpg"
                        _ = try await client.storage
                            .from(storageBucket)
                            .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: true))
                        uploadedPaths.append(path)
                        let publicURL = try client.storage.from(storageBucket).getPublicURL(path: path)
                        insertPayloads.append(NewPostImage(
                            post_id: postID,
                            url: publicURL.absoluteString,
                            position: index
                        ))
                    }
                    if !insertPayloads.isEmpty {
                        try await client.from("post_images").insert(insertPayloads).execute()
                    }
                } catch {
                    if !uploadedPaths.isEmpty {
                        _ = try? await client.storage.from(storageBucket).remove(paths: uploadedPaths)
                    }
                    _ = try? await client
                        .from("posts")
                        .delete()
                        .eq("id", value: postID.uuidString)
                        .eq("owner_user_id", value: userID.uuidString)
                        .execute()
                    let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    print("[PostsService] 图片处理失败（已回滚动态与存储文件）: \(msg)")
                    throw error
                }
            }

            await loadFeed(followingIDs: followingIDs, currentUserID: userID)
            errorMessage = nil
            // Instrumentation: emitted only on the success path (the
            // feed reload above has already settled). Dimensional
            // properties only — caption is user-authored text and
            // deliberately NOT logged; we capture its presence as a
            // bool so cohorting can answer "do captioned posts
            // correlate with retention".
            AnalyticsService.shared.log(.postCreate, properties: [
                "image_count": .int(imageData.count),
                "has_caption": .bool(!caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ])
            return true
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            print("[PostsService] createPost 失败: \(msg)")
            errorMessage = msg
            return false
        }
    }

    // MARK: - Delete Post

    func deletePost(_ postID: UUID, userID: UUID) async {
        errorMessage = nil
        do {
            let storagePaths = storagePathsForPost(postID, userID: userID)
            if !storagePaths.isEmpty {
                _ = try? await client.storage.from(storageBucket).remove(paths: storagePaths)
            }

            try await client
                .from("posts")
                .delete()
                .eq("id", value: postID.uuidString)
                .eq("owner_user_id", value: userID.uuidString)
                .execute()
            feedPosts.removeAll { $0.id == postID }
            userPosts.removeAll { $0.id == postID }
            petPosts.removeAll { $0.id == postID }
            commentCounts[postID] = nil
            commentPreviews[postID] = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Pet cache sync

    /// Rewrites every cached post whose `pet_id` matches `pet.id` so the
    /// joined `pets` snapshot reflects the updated pet. Used after the
    /// owner changes their pet's avatar / accessory — without this, the
    /// feed keeps rendering the stale pet state (e.g. the illustrated
    /// `DogAvatar` fallback because the pre-upload snapshot had no
    /// `avatar_url`) until a hard refresh.
    ///
    /// Rebuilds each matching post because `RemotePost.pets` is a `let`
    /// (the model is a value type captured at JOIN time). The
    /// non-matching posts are returned as-is so `@Published` only
    /// re-emits for arrays that actually changed. Idempotent — calling
    /// this with a pet whose snapshot already matches is a no-op.
    func patchPet(_ pet: RemotePet) {
        func rewrite(_ post: RemotePost) -> RemotePost {
            guard post.pet_id == pet.id else { return post }
            // If the joined snapshot is already the same, skip the
            // rebuild so we don't churn `@Published` subscribers.
            if post.pets == pet { return post }
            return RemotePost(
                id: post.id,
                owner_user_id: post.owner_user_id,
                pet_id: post.pet_id,
                caption: post.caption,
                mood: post.mood,
                created_at: post.created_at,
                pets: pet,
                profiles: post.profiles,
                post_images: post.post_images,
                likes: post.likes,
                comments: post.comments
            )
        }
        feedPosts = feedPosts.map(rewrite)
        userPosts = userPosts.map(rewrite)
        petPosts = petPosts.map(rewrite)
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
                // Instrumentation: emit only on insert (NOT on unlike —
                // "like" count is the viral-loop signal, and counting
                // unlikes would pollute it).
                AnalyticsService.shared.log(.like, properties: [
                    "post_id": .string(postID.uuidString)
                ])
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

    /// Fetches the real like list for one post and updates feed/user posts in place.
    private func syncLikes(for postID: UUID) async {
        guard let likes = try? await client
            .from("likes")
            .select("user_id")
            .eq("post_id", value: postID.uuidString)
            .execute()
            .value as [RemoteLike]
        else { return }

        if let index = feedPosts.firstIndex(where: { $0.id == postID }) {
            feedPosts[index].likes = likes
        }
        if let index = userPosts.firstIndex(where: { $0.id == postID }) {
            userPosts[index].likes = likes
        }
    }

    private func refreshLikes(for postIDs: [UUID]) async {
        guard !postIDs.isEmpty else { return }

        do {
            let rows: [LikeRow] = try await client
                .from("likes")
                .select("post_id, user_id")
                .in("post_id", values: postIDs.map(\.uuidString))
                .execute()
                .value

            let grouped = Dictionary(grouping: rows, by: \.post_id)
            for postID in postIDs {
                let likes = (grouped[postID] ?? []).map { RemoteLike(user_id: $0.user_id) }
                if let index = feedPosts.firstIndex(where: { $0.id == postID }) {
                    feedPosts[index].likes = likes
                }
                if let index = userPosts.firstIndex(where: { $0.id == postID }) {
                    userPosts[index].likes = likes
                }
                if let index = petPosts.firstIndex(where: { $0.id == postID }) {
                    petPosts[index].likes = likes
                }
            }
        } catch {
            print("[PostsService] refreshLikes 批量查询失败: \(error)")
        }
    }

    private func storagePathsForPost(_ postID: UUID, userID: UUID) -> [String] {
        let candidatePosts = feedPosts + userPosts + petPosts
        let images = candidatePosts.first(where: { $0.id == postID })?.post_images ?? []

        if !images.isEmpty {
            let parsed = images.compactMap { storagePath(from: $0.url) }
            if !parsed.isEmpty {
                return parsed
            }
        }

        return ["\(userID.uuidString)/\(postID.uuidString)"]
    }

    private func storagePath(from publicURL: String) -> String? {
        guard let url = URL(string: publicURL) else { return nil }
        let marker = "/storage/v1/object/public/\(storageBucket)/"
        guard let range = url.absoluteString.range(of: marker) else { return nil }
        return String(url.absoluteString[range.upperBound...])
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
            .in("id", values: authorIDs)
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

        // Instrumentation: comment emitted on successful insert only.
        // Content is user-authored text and deliberately NOT logged —
        // only the post_id dimensional identifier. Delete path does
        // not emit (symmetric with `like` / `unlike`).
        AnalyticsService.shared.log(.comment, properties: [
            "post_id": .string(postID.uuidString)
        ])

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
        // Keep inline preview up-to-date (max 2 most recent)
        var previews = commentPreviews[postID, default: []]
        previews.append(comment)
        if previews.count > 2 { previews = Array(previews.suffix(2)) }
        commentPreviews[postID] = previews
        return comment
    }

    func deleteComment(_ commentID: UUID, postID: UUID, userID: UUID) async -> Bool {
        errorMessage = nil

        do {
            try await client
                .from("comments")
                .delete()
                .eq("id", value: commentID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()

            commentPreviews[postID]?.removeAll { $0.id == commentID }

            let nextCount = max((commentCounts[postID] ?? currentCommentCount(for: postID)) - 1, 0)
            commentCounts[postID] = nextCount
            syncCommentCount(postID: postID, count: nextCount)

            if let index = feedPosts.firstIndex(where: { $0.id == postID }) {
                var updated = feedPosts[index]
                updated.comments.removeAll { $0.id == commentID }
                feedPosts[index] = updated
            }

            if let index = userPosts.firstIndex(where: { $0.id == postID }) {
                var updated = userPosts[index]
                updated.comments.removeAll { $0.id == commentID }
                userPosts[index] = updated
            }

            await refreshCommentCount(for: postID)
            await loadCommentPreviews(for: [postID])
            return true
        } catch {
            errorMessage = "删除评论失败，请重试。"
            print("[PostsService] deleteComment 失败: \(error)")
            return false
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

        if let index = petPosts.firstIndex(where: { $0.id == postID }) {
            var updated = petPosts[index]
            updated.comments = Array(updated.comments.prefix(count))
            while updated.comments.count < count {
                updated.comments.append(RemoteCommentStub(id: UUID()))
            }
            petPosts[index] = updated
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
                .in("id", values: postIDs.map(\.uuidString))
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

    // MARK: - Comment Previews

    /// Batch-fetches the two most-recent comments for each post and stores them
    /// in commentPreviews so feed cards can show them inline without a tap.
    func loadCommentPreviews(for postIDs: [UUID]) async {
        guard !postIDs.isEmpty else { return }

        struct CommentRow: Codable {
            let id: UUID; let post_id: UUID; let user_id: UUID
            let content: String; let created_at: Date
        }
        struct ProfileRow: Codable {
            let id: UUID; let username: String?; let display_name: String?
        }

        do {
            let rows: [CommentRow] = try await client
                .from("comments")
                .select("id, post_id, user_id, content, created_at")
                .in("post_id", values: postIDs.map(\.uuidString))
                .order("created_at", ascending: false)
                .execute()
                .value

            // Keep only the 2 most recent per post (rows already sorted desc)
            var grouped: [UUID: [CommentRow]] = [:]
            for row in rows {
                var arr = grouped[row.post_id, default: []]
                if arr.count < 2 { arr.append(row); grouped[row.post_id] = arr }
            }

            // Batch-fetch author profiles
            let authorIDs = Array(Set(rows.map { $0.user_id.uuidString }))
            var profileMap: [UUID: ProfileRow] = [:]
            if !authorIDs.isEmpty,
               let profiles: [ProfileRow] = try? await client
                .from("profiles")
                .select("id, username, display_name")
                .in("id", values: authorIDs)
                .execute()
                .value {
                for p in profiles { profileMap[p.id] = p }
            }

            // Build preview objects in chronological order
            for (postID, commentRows) in grouped {
                commentPreviews[postID] = commentRows.reversed().map { row in
                    let p = profileMap[row.user_id]
                    return RemoteComment(
                        id: row.id, post_id: row.post_id, user_id: row.user_id,
                        content: row.content, created_at: row.created_at, profiles: nil,
                        username: p?.username, display_name: p?.display_name
                    )
                }
            }
        } catch {
            print("[PostsService] loadCommentPreviews 失败: \(error)")
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
