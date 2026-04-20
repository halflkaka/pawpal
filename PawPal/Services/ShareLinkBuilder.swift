import Foundation

/// Central builder for `pawpal://...` deep-link URLs and their
/// accompanying Chinese share messages. Used by every `ShareLink`
/// affordance in the app so the URL scheme and share copy stay in
/// lockstep — one place to tweak the wording or add a new host.
///
/// The URLs produced here round-trip through `DeepLinkRouter.route(url:)`
/// on devices with PawPal installed: tapping a shared link opens the
/// app and navigates to the target. On devices without the app, the
/// external host (WeChat / 小红书 / Messages / etc.) surfaces the URL
/// as plain text — harmless until we stand up universal links + an
/// associated-domains entitlement (Phase 6 follow-up).
///
/// Every builder defensively falls back to `https://pawpal.app` on
/// failed URL construction. The `pawpal://` scheme shouldn't fail in
/// practice, but a belt-and-braces fallback matches the pattern we
/// already use at call sites (see e.g. `ProfileView.shareURLForSelf`).
///
/// Note on the `pawpal://u/<slug>` profile shape: the slug is usually
/// the user's `@handle` rather than a UUID, because handles make for
/// nicer share text ("pawpal://u/alice" reads cleanly in chat). The
/// current `DeepLinkRouter` accepts `u` as an alias for `profile` and
/// will route the slug back to the profile detail — but only if the
/// slug parses as a UUID today. Handle-resolution (slug → user id via
/// the profiles table) is a separate follow-up; meanwhile the URL is
/// still a valid share artefact because external apps only need it to
/// be well-formed text, not to resolve on the recipient's device.
struct ShareLinkBuilder {
    // MARK: - URL builders

    /// `pawpal://post/<uuid>` — round-trips to `PostDetailView` via
    /// `DeepLinkRouter.route(url:)`'s `post` case.
    static func postURL(postID: UUID) -> URL {
        URL(string: "pawpal://post/\(postID.uuidString)")
            ?? URL(string: "https://pawpal.app")!
    }

    /// `pawpal://pet/<uuid>` — round-trips to `PetProfileView` via
    /// the `pet` case (also used by milestone day-of push notifications).
    static func petURL(petID: UUID) -> URL {
        URL(string: "pawpal://pet/\(petID.uuidString)")
            ?? URL(string: "https://pawpal.app")!
    }

    /// `pawpal://u/<slug>` where `<slug>` is the user's handle when
    /// non-empty, or the UUID as a fallback. Mirrors the shape that
    /// `ProfileView.shareURLForSelf` has been emitting; we centralise
    /// it here so every entry point (self-share, share-a-friend, etc.)
    /// produces the same URL.
    static func profileURL(handle: String?, userID: UUID) -> URL {
        let trimmed = handle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = (trimmed?.isEmpty == false) ? trimmed! : userID.uuidString
        return URL(string: "pawpal://u/\(slug)")
            ?? URL(string: "https://pawpal.app")!
    }

    // MARK: - Share messages (Chinese-first)

    /// Message attached to a post share. When we know the pet the post
    /// is about, we personalise — otherwise a generic fallback.
    static func postShareMessage(petName: String?) -> String {
        let trimmed = petName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = trimmed, !name.isEmpty {
            return "来 PawPal 看看 \(name) 的动态吧 🐾"
        }
        return "来 PawPal 看看这条动态吧 🐾"
    }

    /// Message attached to a pet-profile share. The pet's name is
    /// required here — every call site has it on hand.
    static func petShareMessage(petName: String) -> String {
        "来 PawPal 认识一下 \(petName) 🐾"
    }

    /// Message attached to a user-profile share. Kept in sync with
    /// the original copy that lived inline in `ProfileView`.
    static func profileShareMessage(displayName: String) -> String {
        "来 PawPal 看看 \(displayName) 的毛孩子吧 🐾"
    }
}
