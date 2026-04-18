import SwiftUI

@main
struct PetHealthApp: App {
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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
