import Foundation

struct RemotePet: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let owner_user_id: UUID
    var name: String
    var species: String?
    var breed: String?
    var sex: String?
    /// ISO `date` column on `public.pets` (created in migration 001,
    /// line 23 of `supabase/001_schema.sql`). Optional — pre-existing
    /// rows and the add-pet sheet both let this stay nil, and the
    /// milestone surfaces degrade gracefully when it's missing.
    ///
    /// NOTE: PostgREST serialises a `date` column as a bare
    /// `"YYYY-MM-DD"` string (no time component). The Supabase Swift
    /// client's default `Date` decoding strategy expects an ISO8601
    /// *timestamp*, so the synthesised `Codable` used to fail with
    /// "the data couldn't be read because it isn't in the correct
    /// format" on every pet read back after a birthday was set. We
    /// take over `init(from:)` and `encode(to:)` below so `birthday`
    /// round-trips through the custom `birthdayFormatter` (`yyyy-MM-dd`,
    /// UTC, POSIX locale) — which is also what `PetsService`
    /// `NewPet` / `PetUpdate` payloads now encode on the write side.
    var birthday: Date?
    var age_text: String?
    var weight: String?
    var home_city: String?
    var bio: String?
    var avatar_url: String?
    /// Cumulative boop count incremented by the virtual pet's tap-to-boop
    /// (CHANGELOG #38). Optional because older rows — and select statements
    /// that predate migration 013 — won't include the column. UI code
    /// should read via `pet.boop_count ?? 0`.
    var boop_count: Int?
    /// Persisted virtual-pet accessory ('none' / 'bow' / 'hat' /
    /// 'glasses'). Added in migration 014 so the dress-up state survives
    /// between sessions. Nil is treated as 'none' — if the column is
    /// missing (pre-migration clients) the renderer falls back cleanly.
    var accessory: String?
    /// Opt-in gate for playdate invitations (migration 023). When
    /// nil / false, the 约遛弯 pill stays hidden on the pet's profile
    /// and the BEFORE INSERT trigger on `playdates` rejects any
    /// attempt to invite this pet. Defaults to false server-side;
    /// optional here so older select statements that predate migration
    /// 023 still decode cleanly.
    var open_to_playdates: Bool?

    var hometown: String? {
        get { home_city }
        set { home_city = newValue }
    }
    let created_at: Date

    var age: String? {
        get { age_text }
        set { age_text = newValue }
    }

    // MARK: - Birthday formatting

    /// Shared formatter used to bridge PostgreSQL's `date` wire format
    /// (`YYYY-MM-DD`, no time / no zone) and Swift's `Date`. UTC +
    /// POSIX locale makes the conversion deterministic so a birthday
    /// set as 1990-05-15 from any timezone always round-trips to the
    /// same calendar day. `PetsService` uses the same instance when
    /// encoding INSERT / UPDATE payloads so reads and writes stay in
    /// lockstep.
    static let birthdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar   = Calendar(identifier: .gregorian)
        f.locale     = Locale(identifier: "en_US_POSIX")
        f.timeZone   = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case owner_user_id
        case name
        case species
        case breed
        case sex
        case birthday
        case age_text
        case weight
        case home_city
        case bio
        case avatar_url
        case boop_count
        case accessory
        case open_to_playdates
        case created_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(UUID.self, forKey: .id)
        owner_user_id = try c.decode(UUID.self, forKey: .owner_user_id)
        name          = try c.decode(String.self, forKey: .name)
        species       = try c.decodeIfPresent(String.self, forKey: .species)
        breed         = try c.decodeIfPresent(String.self, forKey: .breed)
        sex           = try c.decodeIfPresent(String.self, forKey: .sex)
        age_text      = try c.decodeIfPresent(String.self, forKey: .age_text)
        weight        = try c.decodeIfPresent(String.self, forKey: .weight)
        home_city     = try c.decodeIfPresent(String.self, forKey: .home_city)
        bio           = try c.decodeIfPresent(String.self, forKey: .bio)
        avatar_url    = try c.decodeIfPresent(String.self, forKey: .avatar_url)
        boop_count    = try c.decodeIfPresent(Int.self,    forKey: .boop_count)
        accessory     = try c.decodeIfPresent(String.self, forKey: .accessory)
        open_to_playdates = try c.decodeIfPresent(Bool.self, forKey: .open_to_playdates)
        created_at    = try c.decode(Date.self, forKey: .created_at)

        // `birthday` comes back from PostgREST as a bare YYYY-MM-DD
        // string. Fall back gracefully if the column is missing
        // (older installs that predate the canonical 001 schema —
        // see `supabase/021_add_pets_birthday.sql`) or carries an
        // unexpected format.
        if let raw = try c.decodeIfPresent(String.self, forKey: .birthday),
           !raw.isEmpty {
            // Trim to the first 10 chars in case PostgREST ever returns
            // a full timestamp (e.g. if the column is ever widened to
            // timestamptz) — `yyyy-MM-dd` is the canonical prefix.
            let prefix = String(raw.prefix(10))
            birthday = RemotePet.birthdayFormatter.date(from: prefix)
        } else {
            birthday = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(owner_user_id, forKey: .owner_user_id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(species, forKey: .species)
        try c.encodeIfPresent(breed, forKey: .breed)
        try c.encodeIfPresent(sex, forKey: .sex)
        try c.encodeIfPresent(age_text, forKey: .age_text)
        try c.encodeIfPresent(weight, forKey: .weight)
        try c.encodeIfPresent(home_city, forKey: .home_city)
        try c.encodeIfPresent(bio, forKey: .bio)
        try c.encodeIfPresent(avatar_url, forKey: .avatar_url)
        try c.encodeIfPresent(boop_count, forKey: .boop_count)
        try c.encodeIfPresent(accessory, forKey: .accessory)
        try c.encodeIfPresent(open_to_playdates, forKey: .open_to_playdates)
        try c.encode(created_at, forKey: .created_at)

        if let birthday {
            try c.encode(
                RemotePet.birthdayFormatter.string(from: birthday),
                forKey: .birthday
            )
        }
    }
}
