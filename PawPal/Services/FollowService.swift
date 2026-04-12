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
        struct CountRow: Codable { let count: Int }
        do {
            let rows: [CountRow] = try await client
                .from("follows")
                .select("count", head: false)
                .eq("followed_user_id", value: userID.uuidString)
                .execute()
                .value
            return rows.first?.count ?? 0
        } catch {
            print("[FollowService] followerCount 失败: \(error)")
            return 0
        }
    }

    /// IDs to pass to PostsService.loadFeed — includes self so own posts always appear
    func feedFilter(includingSelf selfID: UUID) -> [UUID] {
        Array(followingIDs) + [selfID]
    }
}
