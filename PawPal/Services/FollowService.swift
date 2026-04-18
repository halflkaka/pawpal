import Foundation
import Supabase

@MainActor
final class FollowService: ObservableObject {
    /// IDs of users the current user is following
    @Published private(set) var followingIDs: Set<UUID> = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: SupabaseClient
    private(set) var currentUserID: UUID?

    init() {
        client = SupabaseConfig.client
    }

    // MARK: - Load

    func loadFollowing(for userID: UUID) async {
        currentUserID = userID
        isLoading = true
        defer { isLoading = false }

        struct FollowRow: Codable { let followed_user_id: UUID }
        do {
            let rows: [FollowRow] = try await client
                .from("follows")
                .select("followed_user_id")
                .eq("follower_user_id", value: userID.uuidString)
                .execute()
                .value
            followingIDs = Set(rows.map(\.followed_user_id))
        } catch {
            print("[FollowService] loadFollowing 失败: \(error)")
        }
    }

    // MARK: - Follow / Unfollow

    func follow(targetID: UUID) async {
        guard let me = currentUserID, me != targetID else { return }
        // Optimistic
        followingIDs.insert(targetID)

        do {
            try await client
                .from("follows")
                .insert(["follower_user_id": me.uuidString, "followed_user_id": targetID.uuidString])
                .execute()
        } catch {
            followingIDs.remove(targetID)
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            print("[FollowService] follow 失败: \(msg)")
            errorMessage = "关注失败: \(msg)"
        }
    }

    func unfollow(targetID: UUID) async {
        guard let me = currentUserID else { return }
        // Optimistic
        followingIDs.remove(targetID)

        do {
            try await client
                .from("follows")
                .delete()
                .eq("follower_user_id", value: me.uuidString)
                .eq("followed_user_id", value: targetID.uuidString)
                .execute()
        } catch {
            followingIDs.insert(targetID)
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            print("[FollowService] unfollow 失败: \(msg)")
            errorMessage = "取消关注失败: \(msg)"
        }
    }

    func toggleFollow(targetID: UUID) async {
        if isFollowing(targetID) {
            await unfollow(targetID: targetID)
        } else {
            await follow(targetID: targetID)
        }
    }

    // MARK: - Helpers

    func isFollowing(_ userID: UUID) -> Bool {
        followingIDs.contains(userID)
    }

    func followerCount(for userID: UUID) async -> Int {
        // Select a minimal column and count the returned rows — avoids relying
        // on PostgREST aggregate syntax that may not be enabled on all plans.
        struct FollowRow: Codable { let follower_user_id: UUID }
        do {
            let rows: [FollowRow] = try await client
                .from("follows")
                .select("follower_user_id")
                .eq("followed_user_id", value: userID.uuidString)
                .execute()
                .value
            return rows.count
        } catch {
            print("[FollowService] followerCount 失败: \(error)")
            return 0
        }
    }

    /// IDs to pass to PostsService.loadFeed — includes self so own posts always appear
    func feedFilter(includingSelf selfID: UUID) -> [UUID] {
        Array(followingIDs) + [selfID]
    }

    // MARK: - Follow-list profiles
    //
    // The list views in #46 (关注 / 粉丝 pages) need the full profile
    // rows, not just ids. We run this as a two-step query rather than a
    // join because the `follows` → `profiles` relationship isn't declared
    // as a foreign-key hint in PostgREST, so nested selects return
    // ambiguous-relationship errors. Two queries (ids, then a single
    // `in (…)` filter on profiles) is 2 round-trips but readable and
    // reliable.

    /// Users that `userID` follows. Returns the `RemoteProfile` rows so
    /// the list view can render avatar + handle + display name without a
    /// per-row fetch.
    func loadFollowingProfiles(for userID: UUID) async -> [RemoteProfile] {
        struct FollowRow: Codable { let followed_user_id: UUID }
        do {
            let follows: [FollowRow] = try await client
                .from("follows")
                .select("followed_user_id")
                .eq("follower_user_id", value: userID.uuidString)
                .execute()
                .value
            return try await fetchProfiles(ids: follows.map(\.followed_user_id))
        } catch {
            print("[FollowService] loadFollowingProfiles 失败: \(error)")
            return []
        }
    }

    /// Users that follow `userID`. Symmetric to `loadFollowingProfiles`
    /// — same two-step strategy, flipped filter.
    func loadFollowerProfiles(for userID: UUID) async -> [RemoteProfile] {
        struct FollowRow: Codable { let follower_user_id: UUID }
        do {
            let follows: [FollowRow] = try await client
                .from("follows")
                .select("follower_user_id")
                .eq("followed_user_id", value: userID.uuidString)
                .execute()
                .value
            return try await fetchProfiles(ids: follows.map(\.follower_user_id))
        } catch {
            print("[FollowService] loadFollowerProfiles 失败: \(error)")
            return []
        }
    }

    /// Batch profile fetch. Used by both list loaders above. Returns an
    /// empty array for empty input so callers can chain without a guard.
    private func fetchProfiles(ids: [UUID]) async throws -> [RemoteProfile] {
        guard !ids.isEmpty else { return [] }
        let list = ids.map { $0.uuidString }.joined(separator: ",")
        let rows: [RemoteProfile] = try await client
            .from("profiles")
            .select()
            .filter("id", operator: "in", value: "(\(list))")
            .execute()
            .value
        return rows
    }
}
