import Foundation

/// One row from `public.playdates` (migration 023). Models the first
/// pet-to-pet graph edge in the schema — the follow graph stays
/// user-to-user (see `docs/decisions.md`); this row connects two pets
/// directly via `proposer_pet_id` / `invitee_pet_id`, with the matching
/// owner user ids denormalised so RLS checks don't need a pets join on
/// every query.
///
/// `scheduled_at`, `created_at`, and `updated_at` are Postgres
/// `timestamptz` columns — Supabase's default ISO8601 `Date` decoder
/// handles them, so (unlike `pets.birthday`'s bare `date`) no custom
/// `init(from:)` / `encode(to:)` is needed.
struct RemotePlaydate: Identifiable, Codable, Equatable, Hashable {
    /// Status transitions: `proposed` → `accepted` | `declined` |
    /// `cancelled`; `accepted` → `cancelled` | `completed`. Matches the
    /// CHECK constraint in `supabase/023_playdates.sql`.
    enum Status: String, Codable, Hashable {
        case proposed, accepted, declined, cancelled, completed
    }

    let id: UUID
    let proposer_pet_id: UUID
    let invitee_pet_id: UUID
    let proposer_user_id: UUID
    let invitee_user_id: UUID
    let scheduled_at: Date
    var location_name: String
    var location_lat: Double?
    var location_lng: Double?
    var status: Status
    var message: String?
    let created_at: Date
    let updated_at: Date

    // MARK: - Series (migration 027)
    //
    // `series_id` groups the 4 playdate rows that belong to the same
    // weekly-repeat series. Both columns are null for one-off
    // playdates — the optional types here are the source of truth for
    // "is this a series instance?" (`isSeriesInstance` below).
    //
    // Decoded as optional so rows that pre-date migration 027 (or are
    // returned by an older PostgREST schema cache) still parse without
    // a custom `init(from:)`. The Swift compiler's synthesised
    // `Codable` handles missing-key + explicit-null both as `nil`.
    let series_id: UUID?
    let series_sequence: Int?

    // MARK: - Participants (migration 028)
    //
    // Optional PostgREST embed from
    // `playdate_participants(*, pets(*), profiles(*))`. Non-nil when a
    // fetch explicitly requests the embed; nil on compact list loads
    // that skip it. The junction table is the canonical source of
    // truth for "which pets are going" — the legacy
    // `proposer_pet_id` / `invitee_pet_id` columns on the parent row
    // are denormalised fast-path fields kept for backward
    // compatibility with the 1:1 code paths.
    //
    // For 1:1 playdates this array has length 2 (proposer + invitee);
    // for group playdates it's 3 (proposer + 2 invitees). See
    // migration 028 for the 2-3 participant cap.
    let playdate_participants: [RemotePlaydateParticipant]?
}

// MARK: - Viewer-relative helpers
//
// Every playdate row has a proposer side and an invitee side; most UI
// surfaces (the My Playdates list, feed cards, copy like "和 X 遛弯")
// just want "the other pet" / "the other owner" relative to whoever's
// looking. These helpers centralise that flip so callers don't repeat
// the ternary at every call site.
//
// When `currentUserID` matches neither side (shouldn't happen for rows
// surfaced to the viewer — RLS only returns rows where auth.uid() is
// proposer or invitee), we default to the invitee side since that's the
// conventional "other" from the proposer's POV.
extension RemotePlaydate {
    func otherPetId(for currentUserID: UUID) -> UUID {
        currentUserID == proposer_user_id ? invitee_pet_id : proposer_pet_id
    }

    func otherOwnerId(for currentUserID: UUID) -> UUID {
        currentUserID == proposer_user_id ? invitee_user_id : proposer_user_id
    }

    /// True when `currentUserID` is the proposer on this row. Small
    /// sugar so list rows can badge "sent" vs "received" without the
    /// caller comparing ids inline.
    func isProposer(for currentUserID: UUID) -> Bool {
        currentUserID == proposer_user_id
    }

    /// True when this row is part of a weekly-repeat series (migration
    /// 027). Wrapped so call sites read as intent rather than a bare
    /// nil-check against an implementation detail.
    var isSeriesInstance: Bool {
        series_id != nil
    }

    // MARK: - Participant helpers (migration 028)
    //
    // When the embed isn't loaded these fall back to the denormalised
    // columns — 1:1 playdates synthesise a plausible two-element view
    // so legacy callers don't have to special-case "junction missing".
    // Group playdates always carry the embed (the composer populates
    // it post-insert via a fetch that includes the embed string).

    /// All junction rows if the embed was fetched; nil if it wasn't.
    /// Most call sites prefer `participantsOrLegacy` which has a
    /// defined fallback.
    var participants: [RemotePlaydateParticipant]? {
        playdate_participants
    }

    /// Pets participating in this playdate (from the embed only —
    /// returns nil when the embed wasn't fetched). Use
    /// `isGroupPlaydate` with the cached detail fetch as the authority.
    var participantPets: [RemotePet] {
        (playdate_participants ?? []).compactMap { $0.pets }
    }

    /// True when the playdate has more than 2 participants (i.e. at
    /// least two invitees). Requires the embed to be loaded — returns
    /// false when the embed is nil, which is the safe default for
    /// legacy call paths that assume 1:1.
    var isGroupPlaydate: Bool {
        (playdate_participants?.count ?? 0) > 2
    }
}
