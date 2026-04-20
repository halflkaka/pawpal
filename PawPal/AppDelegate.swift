import UIKit
import UserNotifications

/// Minimal UIKit bridge — we use `@UIApplicationDelegateAdaptor` in
/// `PawPalApp` so SwiftUI's App lifecycle still drives everything, but
/// APNs callbacks (device token, registration errors, notification
/// taps) only land on a `UIApplicationDelegate` / `UNUserNotificationCenterDelegate`.
///
/// This class forwards every callback to `PushService` (token lifecycle)
/// or `DeepLinkRouter` (tap routing) and does nothing else. Keep it
/// small — any logic past "parse + forward" belongs in the service layer
/// so it's testable without a real AppDelegate instance.
///
/// Class-level `@MainActor` is intentionally omitted: UIKit only
/// guarantees these callbacks arrive on the main thread, and annotating
/// the class would force every other delegate method we might add to
/// be main-actor isolated too. The bodies hop onto the main actor
/// explicitly via `Task { @MainActor in … }` so the compiler can see
/// the isolation boundary at each call site.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Installing the delegate as early as possible ensures a push
        // that relaunches the app cold (AppDelegate → SwiftUI scene
        // creation → user tap) is routed through the same code path
        // as a foreground tap. If the delegate was installed later,
        // cold-start taps would fall through to the "no delegate" path
        // and never reach DeepLinkRouter.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // MARK: - APNs token lifecycle

    /// Forwards the raw APNs token to `PushService`. The service owns
    /// hex conversion + UserDefaults caching + Supabase upsert; this
    /// shim exists only because UIKit refuses to deliver the callback
    /// anywhere else.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            await PushService.shared.handleAPNsToken(deviceToken)
        }
    }

    /// Surfaces APNs registration failures to the service so a future
    /// Settings pane can render the diagnostic. We don't retry here —
    /// the OS will re-invoke registration on the next app launch once
    /// the blocking condition (airplane mode, dev profile mismatch,
    /// etc.) resolves.
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushService.shared.handleRegistrationError(error)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Banners while the app is foregrounded. Default iOS behaviour is
    /// to silently swallow pushes for the active app; for PawPal the
    /// social signals (like / comment / follow) are low-intrusion and
    /// valuable even when the user is already in the app — a new
    /// comment should still nudge. Returning `[.banner, .sound, .badge]`
    /// shows the standard system banner.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// User tapped (or swiped-away on an action button) a notification.
    /// We only care about the tap case (`actionIdentifier ==
    /// UNNotificationDefaultActionIdentifier`) for v1 — action buttons
    /// are a v1.5 item. Parses `type` + `target_id` from the payload
    /// and hands off to `DeepLinkRouter` to drive the tab switch +
    /// push. Always invokes the completion handler so iOS releases the
    /// notification.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let type = userInfo["type"] as? String
        let targetIDString = userInfo["target_id"] as? String
        let targetID = targetIDString.flatMap { UUID(uuidString: $0) }

        if let type, let targetID {
            Task { @MainActor in
                DeepLinkRouter.shared.route(type: type, targetID: targetID)
            }
        } else {
            // Unknown payload shape — log and drop. Still call the
            // completion handler below so iOS doesn't think we're
            // still processing.
            print("[AppDelegate] 通知 payload 缺少 type/target_id: \(userInfo)")
        }

        completionHandler()
    }
}
