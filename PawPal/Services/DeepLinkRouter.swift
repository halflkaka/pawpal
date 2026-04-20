import Foundation
import Combine

/// Central router for push-notification taps and `pawpal://` URL opens.
///
/// The wiring looks like:
///   * `AppDelegate.userNotificationCenter(_:didReceive:)` parses the push
///     payload's `type` + `target_id` and calls `route(type:targetID:)`.
///   * `ContentView.onOpenURL` parses `pawpal://post/<uuid>` style URLs
///     and calls `route(url:)`.
///   * `MainTabView` observes `pendingRoute`; when it changes, the tab
///     bar switches tabs and pushes the relevant detail view onto that
///     tab's NavigationStack, then calls `consume()` to clear the flag.
///
/// Keeping this singleton lets any surface (AppDelegate, URL handlers,
/// future in-app inbox) trigger a navigation without knowing about the
/// tab bar's internal state.
@MainActor
final class DeepLinkRouter: ObservableObject {
    /// Shared singleton — matches the PushService / ChatService pattern.
    static let shared = DeepLinkRouter()

    /// The destinations we know how to handle. Matches the three v1
    /// push types from `docs/sessions/2026-04-18-pm-push-notifications.md`
    /// (post, profile, chat). Milestone day-of reminders (birthdays via
    /// `LocalNotificationsService`, and the future memory-loop category)
    /// target a **pet id**, not a user id — `.pet(UUID)` handles both.
    /// Playdate pushes (invited + three device-scheduled reminders) all
    /// target a playdate id — `.playdate(UUID)` takes the user to the
    /// detail view for that row.
    enum Route: Equatable, Hashable {
        case post(UUID)
        case profile(UUID)   // user id
        case pet(UUID)       // pet id — milestone
        case chat(UUID)
        case playdate(UUID)  // playdate id — invited + t_minus_24h / t_minus_1h / t_plus_2h
    }

    /// The navigation that's waiting to be performed. The tab bar reads
    /// this on change, performs the push, then clears it via `consume()`.
    /// `nil` at rest.
    @Published var pendingRoute: Route?

    init() {}

    /// Maps an APNs payload (`type` + `target_id`) onto a `Route`. Types
    /// that collapse onto the same destination — e.g. `like_post` and
    /// `comment_post` both land on `.post(targetID)` — are grouped here
    /// so callers don't have to repeat the mapping.
    ///
    /// Unknown `type` strings are logged and ignored rather than
    /// crashing: server-driven payloads can introduce new types between
    /// app updates and we'd rather no-op than abort.
    func route(type: String, targetID: UUID) {
        switch type {
        case "like_post", "comment_post":
            pendingRoute = .post(targetID)
        case "follow_user":
            pendingRoute = .profile(targetID)
        case "birthday_today", "memory_today":
            pendingRoute = .pet(targetID)
        case "chat_message":
            pendingRoute = .chat(targetID)
        case "playdate_invited",
             "playdate_t_minus_24h",
             "playdate_t_minus_1h",
             "playdate_t_plus_2h":
            pendingRoute = .playdate(targetID)
        default:
            print("[DeepLinkRouter] 未识别的通知类型: \(type)")
        }
    }

    /// Parses a `pawpal://<host>/<uuid>` URL and forwards to the
    /// `route(type:targetID:)` path so both entry points share the same
    /// mapping table. Anything we can't parse logs and no-ops.
    ///
    /// Host → type mapping:
    ///   * `post`         → `like_post` (both link to post detail)
    ///   * `profile`, `u` → `follow_user` (`u` is the short share-link
    ///                      alias emitted by `ShareLinkBuilder.profileURL`;
    ///                      when the slug is a handle rather than a UUID
    ///                      we log and no-op until handle-resolution lands)
    ///   * `pet`          → `birthday_today` (milestone day-of reminder)
    ///   * `chat`         → `chat_message`
    ///   * `playdate`     → `playdate_invited` (all four playdate types
    ///                      collapse onto the same detail view)
    func route(url: URL) {
        guard url.scheme?.lowercased() == "pawpal" else {
            print("[DeepLinkRouter] 未识别的 scheme: \(url.scheme ?? "nil")")
            return
        }

        // Extract "<host>/<uuid>" — URLComponents host + the last non-empty path component.
        let host = url.host?.lowercased() ?? ""
        let components = url.pathComponents.filter { $0 != "/" }
        // Some "pawpal://post/<uuid>" URLs parse with an empty host and
        // the first path component = "post"; accept either shape.
        let resolvedHost = host.isEmpty ? (components.first ?? "") : host
        let idString: String? = {
            if host.isEmpty {
                // pawpal:/post/<uuid>  → components = [post, <uuid>]
                return components.count >= 2 ? components[1] : nil
            } else {
                // pawpal://post/<uuid> → host = post, components = [<uuid>]
                return components.first
            }
        }()

        guard let idString else {
            print("[DeepLinkRouter] 无法解析 URL: \(url.absoluteString)")
            return
        }

        // `u` is the short alias emitted by `ShareLinkBuilder.profileURL`
        // and may carry a handle (non-UUID slug). Until handle-resolution
        // lands we can only navigate when the slug is a UUID; handle-only
        // share links still round-trip correctly to external apps as text,
        // they just no-op on the recipient device for now.
        guard let id = UUID(uuidString: idString) else {
            if resolvedHost == "u" {
                print("[DeepLinkRouter] handle 分享链接待解析: \(idString)")
            } else {
                print("[DeepLinkRouter] 无法解析 URL: \(url.absoluteString)")
            }
            return
        }

        switch resolvedHost {
        case "post":
            route(type: "like_post", targetID: id)
        case "profile", "u":
            route(type: "follow_user", targetID: id)
        case "pet":
            route(type: "birthday_today", targetID: id)
        case "chat":
            route(type: "chat_message", targetID: id)
        case "playdate":
            route(type: "playdate_invited", targetID: id)
        default:
            print("[DeepLinkRouter] 未识别的 host: \(resolvedHost)")
        }
    }

    /// Called by the tab bar after it has performed the navigation, so
    /// the next tap (or URL open) doesn't re-trigger the onChange path.
    /// Returns the cleared route in case the caller wants to log it.
    @discardableResult
    func consume() -> Route? {
        let route = pendingRoute
        pendingRoute = nil
        return route
    }
}
