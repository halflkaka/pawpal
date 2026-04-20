import SwiftUI

@main
struct PetHealthApp: App {
    /// Bridges UIKit's APNs callbacks (device token, remote-notification
    /// registration failures, notification taps) into our SwiftUI app.
    /// AppDelegate forwards every callback to `PushService` /
    /// `DeepLinkRouter`; no logic lives in the adaptor itself.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Bump the shared URLCache so SwiftUI's `AsyncImage` (used for
        // pet avatars in the feed and post photos) has somewhere to
        // store decoded responses. The default cache is ~512KB / ~10MB
        // which gets evicted within a single feed scroll, causing the
        // same avatar URL to re-download on every appearance — and any
        // intermittent load failure shows the illustrated `DogAvatar`
        // fallback instead of the user's photo. With a larger cache,
        // re-appearances of the same URL hit memory and the photo
        // renders immediately.
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,    // 50 MB in-memory
            diskCapacity:   200 * 1024 * 1024,   // 200 MB on disk
            diskPath:       "pawpal-image-cache"
        )

        // Phase 6 instrumentation: one `app_open` per cold launch.
        // Fires before auth restore, so the event is emitted with
        // `user_id = null` on the first launch after install (the
        // INSERT RLS policy on `events` accepts a null `user_id`).
        // Subsequent warm launches hop through scenePhase → active
        // which emits `session_start` instead.
        AnalyticsService.shared.log(.appOpen)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
