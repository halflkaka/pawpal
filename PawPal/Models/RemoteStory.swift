import Foundation

/// Client-side shape of a row in the `stories` table (migration 018).
///
/// Mirrors the column names exactly (snake_case) so the default Codable
/// synthesis lines up with PostgREST's response. Joined relations land
/// under their PostgreSQL table name (`pets`, `profiles`) — we rename
/// them to `pet` / `owner` in the manual `CodingKeys` + `init(from:)`
/// so call sites read naturally (`story.owner?.username`) instead of
/// reaching through the raw table name. This matches the pattern used
/// by `RemotePost`'s `pets` / `profiles` → `pet` / `owner` aliasing.
struct RemoteStory: Codable, Identifiable, Hashable {
    let id: UUID
    let owner_user_id: UUID
    let pet_id: UUID
    let media_url: String
    /// "image" or "video" — the DB CHECK constraint rejects other values,
    /// but a forward-compatible string keeps this struct usable if we add
    /// more media kinds later.
    let media_type: String
    let caption: String?
    let created_at: Date
    let expires_at: Date

    // Joined rows. Optional because the fallback SELECT path (if the
    // `profiles!owner_user_id(*)` FK hint isn't known on the server) can
    // return a story without them, and callers should degrade to "no
    // avatar / no owner name" rather than crashing.
    var pet: RemotePet?
    var owner: RemoteProfile?

    /// True once the server-issued expiry has passed. Clients should
    /// still trust the DB's RLS filter as the source of truth — this is
    /// a cheap in-memory check to hide a story that just crossed the
    /// 24h mark while the user had the app open.
    var isExpired: Bool { expires_at < Date() }

    // MARK: - Equatable / Hashable via `id`

    static func == (lhs: RemoteStory, rhs: RemoteStory) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: - Codable

    /// PostgREST returns joined relations under the raw table name:
    /// `pets(...)` → `pets` key, `profiles!owner_user_id(*)` → `profiles`
    /// key. We decode through those keys then surface them under the
    /// friendlier `pet` / `owner` names — matches `RemotePost`.
    enum CodingKeys: String, CodingKey {
        case id
        case owner_user_id
        case pet_id
        case media_url
        case media_type
        case caption
        case created_at
        case expires_at
        case pets
        case profiles
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self,   forKey: .id)
        owner_user_id  = try c.decode(UUID.self,   forKey: .owner_user_id)
        pet_id         = try c.decode(UUID.self,   forKey: .pet_id)
        media_url      = try c.decode(String.self, forKey: .media_url)
        media_type     = (try? c.decode(String.self, forKey: .media_type)) ?? "image"
        caption        = try c.decodeIfPresent(String.self, forKey: .caption)
        created_at     = try c.decode(Date.self,   forKey: .created_at)
        expires_at     = try c.decode(Date.self,   forKey: .expires_at)
        pet            = try c.decodeIfPresent(RemotePet.self,     forKey: .pets)
        owner          = try c.decodeIfPresent(RemoteProfile.self, forKey: .profiles)
    }

    /// Encode back into the raw column shape. `pet` / `owner` are
    /// intentionally omitted — stories INSERTs never include joined
    /// relations (they're server-computed on the way out), and emitting
    /// them here would produce keys PostgREST rejects.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,            forKey: .id)
        try c.encode(owner_user_id, forKey: .owner_user_id)
        try c.encode(pet_id,        forKey: .pet_id)
        try c.encode(media_url,     forKey: .media_url)
        try c.encode(media_type,    forKey: .media_type)
        try c.encodeIfPresent(caption, forKey: .caption)
        try c.encode(created_at,    forKey: .created_at)
        try c.encode(expires_at,    forKey: .expires_at)
    }

    /// Convenience initialiser for tests / previews that don't go
    /// through the decoder.
    init(
        id: UUID,
        owner_user_id: UUID,
        pet_id: UUID,
        media_url: String,
        media_type: String = "image",
        caption: String? = nil,
        created_at: Date,
        expires_at: Date,
        pet: RemotePet? = nil,
        owner: RemoteProfile? = nil
    ) {
        self.id = id
        self.owner_user_id = owner_user_id
        self.pet_id = pet_id
        self.media_url = media_url
        self.media_type = media_type
        self.caption = caption
        self.created_at = created_at
        self.expires_at = expires_at
        self.pet = pet
        self.owner = owner
    }
}
