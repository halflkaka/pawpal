import Foundation

/// One row from `public.playdate_participants` (migration 028). The
/// junction table is the canonical source of truth for "which pets are
/// going on this playdate", with per-pet `status` so each invitee can
/// accept / decline independently. The top-level `playdates.status` is
/// a trigger-derived aggregate over these rows — see migration 028's
/// header comment for the derivation rules.
///
/// For 1:1 playdates the backfill created two rows per legacy row
/// (proposer + invitee), so every playdate in the system has at least
/// two participant rows as of migration 028.
///
/// `role` ∈ `"proposer" | "invitee"`; `status` ∈
/// `"proposed" | "accepted" | "declined" | "cancelled"`. Left as raw
/// strings (not Swift enums) so a future server-side expansion doesn't
/// force a client release — views that care about specific values
/// compare against string literals.
///
/// `pets` / `profiles` are the PostgREST embeds that fetches request
/// via `playdate_participants(*, pets(*), profiles(*))`. Both are
/// optional so list-only fetches (without the embed) still decode.
///
/// Note: we deliberately omit `Sendable` conformance — `RemoteProfile`
/// has `var` stored properties which break the auto-synth, and the
/// participant rows are only read from `@MainActor`-isolated services
/// anyway (same rule as `RemotePlaydate`).
struct RemotePlaydateParticipant: Codable, Identifiable, Hashable {
    let playdate_id: UUID
    let pet_id: UUID
    let user_id: UUID
    let role: String   // "proposer" | "invitee"
    let status: String // "proposed" | "accepted" | "declined" | "cancelled"
    let joined_at: Date

    // Embedded sibling rows from the PostgREST `*,embed(*)` syntax.
    // Optional so fetches that skip the embed still decode; non-nil on
    // the detail / list fetches that opt in.
    let pets: RemotePet?
    let profiles: RemoteProfile?

    /// Synthetic id combining both halves of the composite primary key.
    /// `Identifiable` conformance is what lets `ForEach(participants)`
    /// render without an explicit `id:` keypath.
    var id: String { "\(playdate_id)-\(pet_id)" }
}

// MARK: - Status helpers
//
// Small sugar so call sites can ask "did this pet accept?" / "is this
// the proposer row?" without string-compare noise scattered through
// the views.
extension RemotePlaydateParticipant {
    var isProposerRow: Bool { role == "proposer" }
    var isInviteeRow: Bool  { role == "invitee" }

    var isAccepted: Bool  { status == "accepted" }
    var isDeclined: Bool  { status == "declined" }
    var isCancelled: Bool { status == "cancelled" }
    var isProposed: Bool  { status == "proposed" }
}

// Note: `RemoteProfile` declares its own `Hashable` conformance inline
// in `ProfileService.swift`. Swift auto-synthesis of `hash(into:)`
// requires the conformance to sit on the struct declaration itself
// (not in a sibling-file extension), so the conformance lives there
// rather than here. `RemotePet` is already `Hashable` by declaration.
