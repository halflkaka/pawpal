import Foundation

/// One row from `public.story_views` (migration 024). A "seen by"
/// receipt recorded when a pet opens a story. Owners read these rows
/// through `StoryService.viewers(storyID:)`; non-owners never see
/// them — RLS restricts SELECT to the story's owner.
///
/// Mirrors `RemoteStory`'s column-exact Codable shape so the default
/// synthesis lines up with PostgREST's snake_case response. The joined
/// viewer pet lands under the PostgREST alias `viewer_pet` (declared in
/// the select clause as `viewer_pet:pets!viewer_pet_id(*)` — same
/// pattern `PlaydateService.fetch` uses for the proposer / invitee
/// pets) and is surfaced under the friendlier `pet` accessor via
/// manual `CodingKeys` + `init(from:)`.
///
/// The row-level primary key in Postgres is the composite
/// `(story_id, viewer_pet_id)`. Swift needs a scalar `Identifiable`
/// key, so we synthesise `id` from that composite — uniqueness matches
/// the DB constraint exactly.
struct RemoteStoryView: Codable, Identifiable, Hashable {
    let story_id: UUID
    let viewer_pet_id: UUID
    let viewer_user_id: UUID
    let viewed_at: Date

    /// Joined viewer pet. Optional because the fallback SELECT path
    /// (if the embedded select wasn't requested) can return the row
    /// without it; callers should degrade to a placeholder rather
    /// than crashing.
    var pet: RemotePet?

    /// Synthetic scalar id for SwiftUI's `Identifiable`. Combines the
    /// two primary-key columns so a story viewed by multiple of a
    /// single user's pets (edge case) still has distinct row ids.
    var id: String { "\(story_id.uuidString)-\(viewer_pet_id.uuidString)" }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case story_id
        case viewer_pet_id
        case viewer_user_id
        case viewed_at
        case viewer_pet
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        story_id       = try c.decode(UUID.self, forKey: .story_id)
        viewer_pet_id  = try c.decode(UUID.self, forKey: .viewer_pet_id)
        viewer_user_id = try c.decode(UUID.self, forKey: .viewer_user_id)
        viewed_at      = try c.decode(Date.self, forKey: .viewed_at)
        pet            = try c.decodeIfPresent(RemotePet.self, forKey: .viewer_pet)
    }

    /// Encode back into the raw column shape. `pet` is intentionally
    /// omitted — the insert path in `StoryService.recordView` sends
    /// only the three keying columns and lets the DB default
    /// `viewed_at`. Emitting the joined relation on write would
    /// produce a key PostgREST rejects.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(story_id,       forKey: .story_id)
        try c.encode(viewer_pet_id,  forKey: .viewer_pet_id)
        try c.encode(viewer_user_id, forKey: .viewer_user_id)
        try c.encode(viewed_at,      forKey: .viewed_at)
    }

    /// Convenience initialiser for tests / previews that don't go
    /// through the decoder.
    init(
        story_id: UUID,
        viewer_pet_id: UUID,
        viewer_user_id: UUID,
        viewed_at: Date,
        pet: RemotePet? = nil
    ) {
        self.story_id = story_id
        self.viewer_pet_id = viewer_pet_id
        self.viewer_user_id = viewer_user_id
        self.viewed_at = viewed_at
        self.pet = pet
    }
}
