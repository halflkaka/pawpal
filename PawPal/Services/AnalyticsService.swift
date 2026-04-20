import Foundation
import Supabase

// TODO(analytics-opt-out): v1.5 should introduce a user-facing opt-out
// toggle plus an iOS ATT-style priming sheet if we ever ship in markets
// that require it. Chinese iOS market (our primary audience) does not
// require ATT for first-party, server-side analytics, and PawPal's event
// log carries no device / advertising identifier, no IP address, and
// no precise location — only `user_id` + dimensional event metadata
// (counts, enums, ids that already live in the DB). Until that opt-out
// ships, every authenticated user contributes events; the pipeline is
// designed so turning it off is a one-line early-return in `log(_:)`.

/// First-party event logger backing Phase 6 instrumentation — D7
/// retention, posts/DAU, sessions/week.
///
/// Writes to the `public.events` table from migration 025. The table
/// has an INSERT RLS policy that accepts either `user_id is null`
/// (pre-auth emission) or `auth.uid() = user_id`; the analytics
/// pipeline runs server-side as `service_role` (no client SELECT
/// policy). See `docs/decisions.md` → "First-party event log; no
/// third-party analytics SDK" for the why.
///
/// Semantics of this service:
///
///   * **Fire-and-forget.** Every call dispatches a detached `Task`
///     and returns to the caller immediately. User-facing flows MUST
///     NOT await analytics — `log(_:)` is non-throwing by design. A
///     failure on the insert side (network, RLS, unauthenticated,
///     5xx from Supabase) is logged via `print("[Analytics] … 失败")`
///     and swallowed, matching every other service in the app.
///
///   * **No PII beyond `user_id`.** Properties should be
///     dimensional — counts, enums, UUIDs that already exist in the
///     DB. Never include device identifiers, IP addresses, precise
///     location, contact info, message bodies, or any secret material.
///
///   * **Additive event kinds.** Adding a new case to `Kind` ships
///     without a schema migration — `events.properties jsonb` is the
///     open slot. The initial set of kinds is documented both here
///     and in the migration header.
///
///   * **`session_start` dedupe.** Emitted on every scenePhase →
///     active transition, on successful signIn, and on successful
///     signUp. Deduplicated client-side via `lastSessionAt` so a
///     user who rapidly background/foregrounds the app does not
///     flood the table with a session per scenePhase flip. The
///     30-minute window matches industry convention for "is this the
///     same session or a new one" — short enough to catch a real
///     return-to-app, long enough to discount incidental toggles.
@MainActor
final class AnalyticsService {
    /// Shared singleton — matches `AuthManager`, `PostsService`,
    /// `StoryService`, `PlaydateService`, `PushService`,
    /// `LocalNotificationsService`. One logger per process; no
    /// per-view instances.
    static let shared = AnalyticsService()

    /// Supabase client. Mirrors every other service in the app — all
    /// writes share the same authenticated session so RLS
    /// (`auth.uid() = user_id`) resolves consistently. See
    /// `docs/decisions.md` → "Shared Supabase client across services".
    private let client: SupabaseClient

    /// Last emitted `session_start` timestamp. Used by
    /// `logSessionStart()` to debounce scenePhase → active flips and
    /// the signIn / signUp call sites down to at most one per 30
    /// minutes. A `Date?` is enough; we never need the history.
    private var lastSessionAt: Date?

    /// 30-minute session window. Matches Google Analytics / Firebase
    /// defaults. See `logSessionStart()` for the dedupe rationale.
    private static let sessionWindow: TimeInterval = 30 * 60

    private init() {
        client = SupabaseConfig.client
    }

    // MARK: - Public API

    /// Fire-and-forget event emission. Dispatches a detached task so
    /// the caller returns immediately without waiting on the network.
    /// Pass `properties` as a `[String: AnalyticsValue]` dictionary —
    /// the wrapper type encodes strings, ints, doubles, bools, and
    /// UUIDs uniformly into the `events.properties jsonb` column.
    ///
    /// Failure handling: log + swallow. Analytics must never break a
    /// user-facing flow. If the caller is offline, unauthenticated,
    /// or the insert is otherwise rejected, the event is silently
    /// dropped after a `[Analytics] <kind> 失败: …` console line.
    func log(_ kind: Kind, properties: [String: AnalyticsValue]? = nil) {
        // Snapshot `client` so the detached task doesn't cross the
        // MainActor boundary to re-read `self`. Same capture pattern
        // `PlaydateService.currentUserID` uses when it hops off the
        // main actor.
        let client = self.client
        let clientAt = Date()

        Task.detached {
            // Resolve the authenticated user id inside the detached
            // task so we don't cross actor boundaries. A nil id is
            // fine — the INSERT RLS policy accepts `user_id is null`
            // for pre-auth events (e.g. `app_open` fired from the
            // App struct before `AuthManager.restoreSession` has
            // completed).
            let userID: UUID? = try? await client.auth.session.user.id

            let row = EventInsert(
                user_id: userID,
                kind: kind.rawValue,
                properties: properties,
                client_at: clientAt
            )

            do {
                try await client
                    .from("events")
                    .insert(row)
                    .execute()
            } catch {
                // Swallow. A failed analytics insert is never worth
                // disrupting the user; the read pipeline tolerates
                // missing rows.
                print("[Analytics] \(kind.rawValue) 失败: \(error)")
            }
        }
    }

    /// `session_start` with the 30-minute client-side dedupe baked in.
    /// Call this from scenePhase → active, and from signIn / signUp
    /// success paths. Repeated calls within the 30-minute window are
    /// no-ops — only the first emits.
    ///
    /// Why client-side instead of server-side: a server-side DISTINCT
    /// query can compute weekly session counts correctly from a noisy
    /// stream, but at the cost of inflating the table ~10-20x with
    /// duplicate rows from incidental scenePhase flips (notification
    /// tap → active → background → active again). Deduping at the
    /// source is cheaper and keeps the raw stream analysable by eye.
    func logSessionStart() {
        let now = Date()
        if let last = lastSessionAt, now.timeIntervalSince(last) < Self.sessionWindow {
            return
        }
        lastSessionAt = now
        log(.sessionStart)
    }

    // MARK: - Insert payload

    /// The row we POST to `events`. Kept private — callers never
    /// construct this directly; they go through `log(_:)`. Using an
    /// explicit `Encodable` struct rather than a `[String: Any]`
    /// dictionary means the Supabase Swift SDK serialises each field
    /// with the correct JSON type (UUIDs as strings, Dates as ISO8601
    /// timestamps, jsonb via the nested AnalyticsValue encoding).
    private struct EventInsert: Encodable {
        let user_id: UUID?
        let kind: String
        let properties: [String: AnalyticsValue]?
        let client_at: Date
    }

    // MARK: - Event kinds

    /// Enumerated event kinds we emit in this PR. New kinds are
    /// additive — adding a case here does not require a schema
    /// migration because `events.properties` is `jsonb` and `kind` is
    /// `text` with no CHECK constraint.
    ///
    /// Mirror this list in `supabase/025_events.sql`'s header block
    /// when adding a case so the catalogue stays discoverable to
    /// analytics authors browsing the migration.
    enum Kind: String {
        case appOpen           = "app_open"
        case sessionStart      = "session_start"
        case signIn            = "sign_in"
        case signUp            = "sign_up"
        case postCreate        = "post_create"
        case storyView         = "story_view"
        case storyPost         = "story_post"
        case playdateProposed  = "playdate_proposed"
        case playdateAccepted  = "playdate_accepted"
        case shareTap          = "share_tap"
        case follow            = "follow"
        case like              = "like"
        case comment           = "comment"
    }
}

// MARK: - AnalyticsValue

/// A tiny sum type for event property values. Swift's existentials
/// (`any Encodable`) don't play nicely with nested Codable inside a
/// struct that crosses Sendable boundaries — we'd lose type info by
/// the time the Supabase encoder sees the dictionary. Wrapping each
/// value in a concrete enum sidesteps that and guarantees the JSON
/// types we emit (`string` / `number` / `bool` / `null`) are exactly
/// what PostgreSQL's `jsonb` expects.
///
/// ExpressibleBy*Literal conformances let call sites write
/// `["image_count": 3, "has_caption": true]` without the enum case
/// noise. UUIDs don't have a matching literal so they go through
/// `.string($0.uuidString)` — same convention as every other
/// service's `.eq("id", value: uuid.uuidString)` call.
enum AnalyticsValue: Encodable, Sendable,
                     ExpressibleByStringLiteral,
                     ExpressibleByIntegerLiteral,
                     ExpressibleByFloatLiteral,
                     ExpressibleByBooleanLiteral {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(stringLiteral value: String)      { self = .string(value) }
    init(integerLiteral value: Int)        { self = .int(value) }
    init(floatLiteral value: Double)       { self = .double(value) }
    init(booleanLiteral value: Bool)       { self = .bool(value) }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v):    try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v):   try container.encode(v)
        case .null:          try container.encodeNil()
        }
    }
}
