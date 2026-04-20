import Foundation
import UIKit
import UserNotifications
import Supabase

/// Push-notification lifecycle — permission priming, APNs token
/// handling, and `device_tokens` upserts against Supabase.
///
/// Matches the pattern used by `ChatService` / `PetsService`:
///   * `@MainActor final class` + `static let shared` singleton
///   * Reads `SupabaseConfig.client` (never instantiates a second one —
///     the shared client is where the authenticated session lives, and
///     RLS policies on `device_tokens` check `auth.uid()` against
///     `user_id` on insert).
///
/// The token callback path (`AppDelegate.didRegisterForRemoteNotifications…`
/// → `handleAPNsToken`) may fire before the user has signed in. In that
/// case we stash the token in `UserDefaults` under
/// `pawpal.apns.lastToken` and upsert it the next time
/// `AuthManager.signIn` / `register` completes. This matches the "token
/// can re-issue at any time" note in the PM doc — every callback
/// replaces the cached token, and the upsert is keyed so the server row
/// ends up idempotent.
@MainActor
final class PushService: ObservableObject {
    /// Shared singleton so the AppDelegate + AuthManager hit the same
    /// in-memory state (authorization status, registration error).
    static let shared = PushService()

    /// OS permission grant state. Drives the inline "通知已关闭" banner
    /// that'll appear on Feed once the user has tapped 以后再说 and then
    /// received a real-but-undelivered notification (future Settings
    /// seam). Starts at `.notDetermined`; refreshed on scenePhase
    /// becoming active.
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Last error surfaced from `didFailToRegisterForRemoteNotifications`.
    /// Kept as plain string so any future settings pane can render it
    /// without re-inspecting NSError domains.
    @Published var registrationError: String?

    /// UserDefaults key for the last APNs token we saw. Stashed on every
    /// AppDelegate callback and re-read on sign-in so a returning user's
    /// session picks up the token without waiting for iOS to re-issue.
    private let tokenDefaultsKey = "pawpal.apns.lastToken"

    private let client: SupabaseClient

    init() {
        self.client = SupabaseConfig.client
    }

    // MARK: - Authorization

    /// Drives the system permission prompt. Called from the onboarding
    /// priming sheet's 开启通知 button — never on cold start, so the
    /// one-shot OS grant isn't burned before the user has seen any
    /// value from the app.
    ///
    /// Returns the grant result so the priming view can branch its
    /// dismiss copy (future polish — v1 just dismisses either way).
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        var granted = false
        do {
            granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("[Push] requestAuthorization 失败: \(error)")
            granted = false
        }

        await refreshAuthorizationStatus()

        if granted {
            // Registration for remote notifications must happen on the
            // main actor — we're already on it thanks to the class-level
            // @MainActor annotation. This kicks off the APNs handshake
            // that lands in AppDelegate's didRegister/didFailToRegister.
            UIApplication.shared.registerForRemoteNotifications()
        }

        return granted
    }

    /// Re-reads the OS authorization status without prompting. Called
    /// on app foreground so a user who flipped the Settings toggle
    /// while the app was backgrounded has the in-app state reflect
    /// reality.
    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        self.authorizationStatus = settings.authorizationStatus
    }

    // MARK: - Token handling

    /// Called from `AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken`.
    /// Converts the raw `Data` to the APNs hex string that the edge
    /// function will POST to, caches it locally, and — if a user is
    /// already signed in at the time of the callback (rare: system
    /// prompt races auth) — upserts immediately.
    ///
    /// The common path is: signed-out user accepts the permission
    /// prompt during onboarding → registerForRemoteNotifications fires
    /// → this callback stores the token → the subsequent signIn path
    /// in AuthManager calls `registerCurrentToken(for:)` and the
    /// server finally gets the row.
    func handleAPNsToken(_ tokenData: Data) async {
        let hex = tokenData.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: tokenDefaultsKey)
        print("[Push] APNs token 已保存 (len=\(hex.count))")

        // Intentionally do NOT push a row here without a known user id:
        // RLS on device_tokens requires `auth.uid() = user_id` on insert,
        // so a pre-auth upsert would fail anyway. AuthManager drives the
        // upsert on sign-in via `registerCurrentToken(for:)`.
    }

    /// Upserts the last-known APNs token for `userID` into the
    /// `device_tokens` table. Idempotent on the composite key so
    /// repeated calls (every sign-in, every token rotation) converge
    /// on one row per (user, token). Safe to call when no token is
    /// cached yet — we just exit.
    ///
    /// Env detection is currently `#if DEBUG` → "sandbox", else
    /// "production". This is correct for local builds + App Store
    /// production but wrong for TestFlight, which ships a release-mode
    /// binary yet uses the sandbox APNs host.
    //
    // TODO(push): read the embedded provisioning profile's
    // `aps-environment` entitlement at runtime so TestFlight builds
    // land in the sandbox bucket. Tracked in docs/known-issues.md.
    func registerCurrentToken(for userID: UUID) async {
        guard let token = UserDefaults.standard.string(forKey: tokenDefaultsKey),
              !token.isEmpty else {
            print("[Push] 无缓存 token,跳过 registerCurrentToken")
            return
        }

        let env: String
        #if DEBUG
        env = "sandbox"
        #else
        env = "production"
        #endif

        struct DeviceTokenUpsert: Encodable {
            let user_id: UUID
            let token: String
            let env: String
            let updated_at: Date
        }

        let payload = DeviceTokenUpsert(
            user_id: userID,
            token: token,
            env: env,
            updated_at: Date()
        )

        do {
            _ = try await client
                .from("device_tokens")
                .upsert(payload, onConflict: "user_id,token")
                .execute()
            print("[Push] device_tokens 已 upsert for user=\(userID)")
        } catch {
            // Non-fatal: the user still gets an in-app experience;
            // they just won't receive pushes until the next sign-in
            // retries. If backend migration 022 hasn't shipped yet
            // this is also the failure mode, and we want the client
            // to keep working.
            print("[Push] register 失败: \(error)")
        }
    }

    /// Deletes the current device's token row for `userID` before sign-out.
    /// Must run BEFORE the Supabase sign-out call so RLS (which checks
    /// `auth.uid() = user_id`) still accepts the DELETE — the session
    /// is torn down by the sign-out, at which point `auth.uid()` is
    /// null and the delete would be silently filtered.
    ///
    /// Per the PM doc, we do NOT call
    /// `unregisterForRemoteNotifications` — the OS-level permission
    /// grant survives sign-out and a subsequent sign-in on the same
    /// device should not re-prompt.
    func clearToken(for userID: UUID) async {
        let token = UserDefaults.standard.string(forKey: tokenDefaultsKey)

        if let token, !token.isEmpty {
            do {
                _ = try await client
                    .from("device_tokens")
                    .delete()
                    .eq("user_id", value: userID.uuidString)
                    .eq("token", value: token)
                    .execute()
                print("[Push] device_tokens 已清除 for user=\(userID)")
            } catch {
                print("[Push] clear 失败: \(error)")
            }
        }

        UserDefaults.standard.removeObject(forKey: tokenDefaultsKey)
    }

    /// Called from `AppDelegate.didFailToRegisterForRemoteNotifications`.
    /// Stores the error string so a future Settings pane can surface it
    /// ("Push registration failed: …") without re-reading the NSError.
    func handleRegistrationError(_ error: Error) {
        self.registrationError = error.localizedDescription
        print("[Push] register failed: \(error)")
    }
}
