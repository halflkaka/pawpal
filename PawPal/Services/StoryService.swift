import Foundation
import UIKit
import Supabase

/// Stories service backed by the `stories` table from migration 018.
/// MVP scope:
///
///   * 24h ephemeral media (image only on the client; schema accepts
///     'video' for a later PR).
///   * Per-pet stories (not per-user) — a user with multiple pets has
///     an independent rail ring for each.
///   * Reads on appear + pull-to-refresh. No realtime subscription yet.
///   * Storage bucket `story-media` — created manually in the Supabase
///     dashboard (public read, authenticated write), matching the
///     `post-images` convention. Paths are `{owner_id}/{story_id}.{ext}`.
///
/// This class is modelled after `ChatService`: a process-wide singleton
/// with `@Published` caches so the home feed rail, pet profile ring, and
/// story viewer all react to the same state.
@MainActor
final class StoryService: ObservableObject {
    /// Shared singleton — matches the pattern used by `ChatService.shared`,
    /// `PetsService.shared`, and `VirtualPetStateStore.shared`. The rail
    /// and viewer screens read from the same cache so a posted story
    /// becomes visible everywhere on the same RunLoop tick.
    static let shared = StoryService()

    /// Active stories grouped by pet. Each bucket is sorted oldest-first
    /// so the viewer can play through them in chronological order (this
    /// matches how Instagram / most stories UIs present a pet's stack).
    ///
    /// "Active" means `expires_at > now()` at the moment the load ran —
    /// clients should refresh periodically to prune stale buckets, but
    /// a stale entry is harmless since `RemoteStory.isExpired` gates
    /// individual rendering too.
    @Published var activeStoriesByPet: [UUID: [RemoteStory]] = [:]

    @Published var errorMessage: String?

    private let client: SupabaseClient
    private let bucket = "story-media"

    /// Held so we can detach in `deinit`. Unlike `PostsService` which
    /// has many short-lived per-view instances, `StoryService` is a
    /// singleton — so in practice this observer lives for the app's
    /// lifetime. We still release it on deinit for correctness.
    private var petUpdateObserver: NSObjectProtocol?

    init() {
        client = SupabaseConfig.client

        // Same rationale as PostsService: when the owner updates a pet's
        // avatar / accessory, cached story rows carry stale per-story
        // JOIN snapshots (`RemoteStory.pet`) and the rail keeps
        // rendering the pre-edit state until the next load. Subscribing
        // to `.petDidUpdate` and re-patching keeps the rail in sync
        // without a manual refresh.
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

    // MARK: - Pet cache sync

    /// Updates cached story rows whose `pet_id` matches the given pet.
    /// `RemoteStory.pet` is a `var`, so we can mutate in place without
    /// rebuilding the row. Broadcast-driven: called from the
    /// `.petDidUpdate` subscriber in `init` whenever PetsService
    /// commits an avatar / accessory / profile edit.
    ///
    /// Idempotent — if the cached snapshot already matches, the
    /// `@Published` setter still fires once per bucket because we
    /// reassign the dictionary, but the rail's diffing (keyed by
    /// `RemoteStory.id`) renders as a no-op.
    func patchPet(_ pet: RemotePet) {
        guard var bucketRows = activeStoriesByPet[pet.id] else { return }
        var changed = false
        for i in bucketRows.indices where bucketRows[i].pet != pet {
            bucketRows[i].pet = pet
            changed = true
        }
        if changed {
            activeStoriesByPet[pet.id] = bucketRows
        }
    }

    // MARK: - Loading

    /// Fetches all active stories, optionally filtered to a set of pet
    /// ids (typically the current user's own pets plus the pets they
    /// follow). Pass `nil` to load every active story globally — useful
    /// for the discovery/explore surface, but the home rail should
    /// always scope down to avoid pulling strangers' stories.
    ///
    /// Groups the flat row list by `pet_id` and stores the result in
    /// `activeStoriesByPet`, sorted oldest-first per pet.
    func loadActiveStories(followedPetIDs: [UUID]? = nil) async {
        errorMessage = nil

        let nowISO = ISO8601DateFormatter().string(from: Date())

        do {
            // Shared query: active stories joined with pet + owner
            // profile so the rail row can render without a second
            // round-trip per pet.
            let selectClause = "*, pets!pet_id(*), profiles!owner_user_id(*)"
            var query = client
                .from("stories")
                .select(selectClause)
                .gt("expires_at", value: nowISO)

            if let ids = followedPetIDs {
                // Explicit filter path for the home rail. An empty list
                // means "no followed pets" — still worth a query so we
                // clear any stale cache rather than skipping the call.
                query = query.in("pet_id", values: ids.map { $0.uuidString })
            }

            let rows: [RemoteStory] = try await query
                .order("created_at", ascending: true)
                .execute()
                .value

            // Group by pet_id. Using Dictionary(grouping:) preserves the
            // order the rows came back in, which is ascending by
            // created_at — so each bucket is already oldest-first.
            let grouped = Dictionary(grouping: rows, by: { $0.pet_id })
            activeStoriesByPet = grouped
        } catch {
            print("[StoryService] loadActiveStories 失败: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Posting

    /// Uploads the story's media blob to the `story-media` bucket, then
    /// inserts the row into `stories`. Returns the inserted row on
    /// success, nil on failure (sets `errorMessage`).
    ///
    /// The upload path is `{owner_id}/{story_id}.{ext}` so each user's
    /// stories live under their own folder prefix — consistent with the
    /// post-images layout and trivially compatible with folder-scoped
    /// storage RLS policies.
    func postStory(
        petID: UUID,
        ownerID: UUID,
        mediaData: Data,
        mediaType: String,
        caption: String?
    ) async -> RemoteStory? {
        errorMessage = nil

        // Pre-generate the id so we can reference the same value in the
        // storage path and the DB insert. Matches the pattern
        // `PostsService.createPost` uses for post images.
        let storyID = UUID()
        let ext = mediaType == "video" ? "mp4" : "jpg"
        let path = "\(ownerID.uuidString)/\(storyID.uuidString).\(ext)"

        // Content-type detection: images go through JPEG compression
        // (mirrors `AvatarService.compress`) so we don't store 5 MB
        // originals. Videos are passed through as-is for the MVP —
        // compression / reencoding will land with the video upload PR.
        let (blob, contentType): (Data, String)
        if mediaType == "video" {
            blob = mediaData
            contentType = "video/mp4"
        } else {
            blob = compressImage(mediaData)
            contentType = "image/jpeg"
        }

        // Step 1: upload the blob. If this fails, skip the DB insert —
        // a story row pointing at a missing media URL would render as
        // a permanent broken image in everyone's rail.
        do {
            _ = try await client.storage
                .from(bucket)
                .upload(
                    path,
                    data: blob,
                    options: FileOptions(contentType: contentType, upsert: true)
                )
        } catch {
            print("[StoryService] postStory 上传 失败: \(error)")
            errorMessage = error.localizedDescription
            return nil
        }

        // Resolve the public URL off the storage layer so we don't have
        // to hardcode the Supabase project host.
        let publicURL: String
        do {
            publicURL = try client.storage
                .from(bucket)
                .getPublicURL(path: path)
                .absoluteString
        } catch {
            print("[StoryService] postStory getPublicURL 失败: \(error)")
            errorMessage = error.localizedDescription
            return nil
        }

        // Step 2: insert the row. We let the DB default the
        // `created_at` / `expires_at` columns so every client starts
        // from the server's clock — avoids TTL drift from devices with
        // skewed system time.
        struct StoryInsert: Encodable {
            let id: UUID
            let owner_user_id: UUID
            let pet_id: UUID
            let media_url: String
            let media_type: String
            let caption: String?
        }
        let payload = StoryInsert(
            id: storyID,
            owner_user_id: ownerID,
            pet_id: petID,
            media_url: publicURL,
            media_type: mediaType,
            caption: caption?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )

        do {
            let inserted: RemoteStory = try await client
                .from("stories")
                .insert(payload)
                .select("*, pets!pet_id(*), profiles!owner_user_id(*)")
                .single()
                .execute()
                .value

            // Optimistically fold the new story into the local cache so
            // the rail ring lights up without a second loadActiveStories
            // round-trip.
            var bucketRows = activeStoriesByPet[petID] ?? []
            bucketRows.append(inserted)
            activeStoriesByPet[petID] = bucketRows
            // Instrumentation: posting a story is a core creation
            // event, mirrors `post_create` for the ephemeral surface.
            AnalyticsService.shared.log(.storyPost)
            return inserted
        } catch {
            // Best-effort cleanup: the blob is already up but the row
            // never landed. Remove the orphan so we don't leak storage.
            _ = try? await client.storage.from(bucket).remove(paths: [path])
            print("[StoryService] postStory insert 失败: \(error)")
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Deletion

    /// Deletes a story row and attempts to remove the associated media
    /// blob. Returns true if the row delete succeeded — blob cleanup is
    /// best-effort because orphan files are harmless (public URL just
    /// 404s) and a failing `remove` shouldn't block the UI from hiding
    /// the story.
    func deleteStory(storyID: UUID) async -> Bool {
        errorMessage = nil

        // Look up the story in the cache so we can derive the storage
        // path without an extra SELECT. If it's not cached (e.g. the
        // viewer was opened deep-linked) we fall back to a DB read.
        // Note: the cache-then-await lookup is split into two statements
        // because Swift's `??` short-circuit can't chain an `await` on
        // its right-hand side cleanly — the async context doesn't
        // propagate through a nested `try? await …` inside a
        // double-optional fallback.
        let cached = activeStoriesByPet.values.flatMap { $0 }.first(where: { $0.id == storyID })
        var mediaURL: String? = cached?.media_url
        if mediaURL == nil {
            mediaURL = try? await fetchMediaURL(for: storyID)
        }

        do {
            try await client
                .from("stories")
                .delete()
                .eq("id", value: storyID.uuidString)
                .execute()

            // Drop from the local cache on success.
            for (petID, stories) in activeStoriesByPet {
                let filtered = stories.filter { $0.id != storyID }
                if filtered.count != stories.count {
                    if filtered.isEmpty {
                        activeStoriesByPet.removeValue(forKey: petID)
                    } else {
                        activeStoriesByPet[petID] = filtered
                    }
                }
            }
        } catch {
            print("[StoryService] deleteStory 失败: \(error)")
            errorMessage = error.localizedDescription
            return false
        }

        // Best-effort blob removal. A failure here doesn't matter to
        // the user — the row is gone and the URL points at storage the
        // viewer can't reach anymore.
        if let mediaURL, let path = storagePath(from: mediaURL) {
            _ = try? await client.storage.from(bucket).remove(paths: [path])
        }
        return true
    }

    // MARK: - Query helpers

    /// Fast O(1) lookup for the rail rendering code: "does this pet
    /// currently have at least one active story?". Reads from the
    /// cache populated by `loadActiveStories`, so callers should have
    /// already triggered a load for the feed's pet set.
    func hasActiveStory(for petID: UUID) -> Bool {
        guard let stories = activeStoriesByPet[petID] else { return false }
        return stories.contains(where: { !$0.isExpired })
    }

    // MARK: - View receipts (migration 024 `story_views`)

    /// Records that `viewerPetID` has seen `storyID`. Safe to call on
    /// every open — `story_views` has a `(story_id, viewer_pet_id)`
    /// primary key and we use `upsert(ignoreDuplicates: true)` so a
    /// repeat open is a cheap no-op at the DB layer rather than a
    /// constraint-violation exception the client has to catch.
    ///
    /// Silent by design: RLS rejections, network blips, and
    /// unauthenticated callers all fail *closed* (we log + swallow).
    /// The caller is a fire-and-forget `Task` inside
    /// `StoryViewerView`, and we'd rather miss a view receipt than
    /// surface a toast to a viewer who was just trying to look at a
    /// story.
    func recordView(storyID: UUID, viewerPetID: UUID) async throws {
        // Pull the user id off the live session. The INSERT RLS policy
        // is `auth.uid() = viewer_user_id`, so we need the caller's
        // own id in the payload — passing it from the view layer
        // would let a stale prop spoof a different user. Belt-and-
        // suspenders: the BEFORE INSERT trigger in migration 024 also
        // verifies `viewer_pet_id` belongs to `viewer_user_id`.
        let viewerUserID: UUID
        do {
            viewerUserID = try await client.auth.session.user.id
        } catch {
            // Unauthenticated — early-exit silently per the docstring.
            // A logged-out user shouldn't be able to reach the viewer
            // anyway, but guarding here means the catch path below
            // doesn't need to disambiguate "no session" from "RLS
            // rejected".
            return
        }

        struct Insert: Encodable {
            let story_id: UUID
            let viewer_pet_id: UUID
            let viewer_user_id: UUID
        }
        let payload = Insert(
            story_id: storyID,
            viewer_pet_id: viewerPetID,
            viewer_user_id: viewerUserID
        )

        do {
            try await client
                .from("story_views")
                .upsert(
                    payload,
                    onConflict: "story_id,viewer_pet_id",
                    ignoreDuplicates: true
                )
                .execute()
            // Instrumentation: emit only on the success path.
            // `ignoreDuplicates: true` means a repeat view returns
            // cleanly without hitting this branch's catch — but
            // `StoryViewerView` already dedupes per-session via
            // `recordedViewIDs`, so in practice one emission = one
            // fresh open.
            AnalyticsService.shared.log(.storyView, properties: [
                "story_id": .string(storyID.uuidString)
            ])
        } catch {
            // Swallow: a failed view receipt is never worth
            // disrupting the viewer's flow. RLS rejections (e.g. the
            // story has already expired and is no longer SELECTable
            // for the join) land here too.
            print("[StoryService] recordView 失败: \(error)")
        }
    }

    /// Counts the viewers for a story. Owner-only by RLS — a non-owner
    /// call returns 0 (the RLS filter eliminates every row before
    /// count aggregation on the server). We also swallow thrown errors
    /// and return 0 in the non-owner / offline case so the caller
    /// doesn't have to special-case it.
    func viewerCount(storyID: UUID) async throws -> Int {
        do {
            let response = try await client
                .from("story_views")
                .select("story_id", head: true, count: .exact)
                .eq("story_id", value: storyID.uuidString)
                .execute()
            return response.count ?? 0
        } catch {
            print("[StoryService] viewerCount 失败: \(error)")
            return 0
        }
    }

    /// Loads the full viewer list for a story, with each viewer's pet
    /// row embedded via PostgREST's `viewer_pet:pets!viewer_pet_id(*)`
    /// alias. Returns [] on RLS rejection / network failure — mirrors
    /// `viewerCount`.
    ///
    /// Sorted newest-first so the owner's sheet shows the most recent
    /// view at the top of the list; the composite index
    /// `story_views_story_id_idx(story_id, viewed_at desc)` from
    /// migration 024 services this query directly.
    func viewers(storyID: UUID) async throws -> [RemoteStoryView] {
        do {
            let rows: [RemoteStoryView] = try await client
                .from("story_views")
                .select("*, viewer_pet:pets!viewer_pet_id(*)")
                .eq("story_id", value: storyID.uuidString)
                .order("viewed_at", ascending: false)
                .execute()
                .value
            return rows
        } catch {
            print("[StoryService] viewers 失败: \(error)")
            return []
        }
    }

    // MARK: - Private helpers

    /// Pulls just the media URL for a single story. Used as a fallback
    /// path in `deleteStory` when the story isn't in the local cache.
    private func fetchMediaURL(for storyID: UUID) async throws -> String? {
        struct Row: Decodable { let media_url: String }
        let rows: [Row] = try await client
            .from("stories")
            .select("media_url")
            .eq("id", value: storyID.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first?.media_url
    }

    /// Converts a Supabase public URL back into a storage-relative
    /// path so `storage.remove` can target it. Same slicing trick as
    /// `PostsService.storagePath(from:)`.
    private func storagePath(from publicURL: String) -> String? {
        guard let url = URL(string: publicURL) else { return nil }
        let marker = "/storage/v1/object/public/\(bucket)/"
        guard let range = url.absoluteString.range(of: marker) else { return nil }
        return String(url.absoluteString[range.upperBound...])
    }

    /// Resize + JPEG-compress an image to keep rail thumbnails under
    /// the mobile-friendly threshold. Matches `AvatarService.compress`
    /// in spirit but uses a larger max edge (1080) because stories are
    /// full-screen surfaces, not 32pt avatar tiles.
    private func compressImage(_ data: Data) -> Data {
        guard let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.85) else { return data }
        let size = image.size
        let maxEdge: CGFloat = 1080
        guard max(size.width, size.height) > maxEdge else { return jpeg }
        let scale = maxEdge / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: 0.85) ?? jpeg
    }
}

private extension String {
    /// Nil-out empty strings so Codable writes `null` instead of `""`.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
