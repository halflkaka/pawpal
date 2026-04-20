import SwiftUI

struct ContentView: View {
    @State private var authManager = AuthManager()
    @State private var hasStartedRestore = false
    /// scenePhase observer — Phase 6 instrumentation uses the `.active`
    /// transition to emit `session_start` events. `AnalyticsService`
    /// debounces repeated emissions down to one per 30 minutes.
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        rootContent
            .animation(.easeInOut(duration: 0.2), value: authManager.currentUser?.id)
            .task {
                guard !hasStartedRestore else { return }
                hasStartedRestore = true
                await authManager.restoreSession()
                // Emit a `session_start` for the initial foreground
                // presentation. scenePhase doesn't toggle on cold
                // launch — it starts at `.active` — so the observer
                // below wouldn't fire for the first session without
                // this explicit call. The 30-minute dedupe in
                // `AnalyticsService.logSessionStart` makes any
                // overlap with a scenePhase-driven call a no-op.
                AnalyticsService.shared.logSessionStart()
            }
            // Emit `session_start` on every foreground entry.
            // `AnalyticsService.logSessionStart` dedupes to at most
            // one per 30 minutes so rapid background/foreground
            // toggling (notification taps, control-centre pulls)
            // doesn't flood the table.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    AnalyticsService.shared.logSessionStart()
                }
            }
            // `pawpal://` URL scheme handling. Registered in Info.plist
            // under CFBundleURLTypes — when iOS opens us via a deep link
            // (future email / SMS / web fallback for push taps) the
            // router parses the URL and MainTabView picks it up through
            // the same `pendingRoute` path used by APNs taps.
            .onOpenURL { url in
                DeepLinkRouter.shared.route(url: url)
            }
    }

    @ViewBuilder
    private var rootContent: some View {
        if authManager.currentUser != nil {
            // We have a user — either from UserDefaults cache (fast path) or a
            // confirmed session. Go straight to the app; restoreSession() will
            // silently validate / refresh the token in the background.
            MainTabView(authManager: authManager)
        } else if authManager.isRestoringSession {
            // No cached user and session check is in-flight — show splash once.
            startupSurface
        } else {
            // Restore finished and no valid session found.
            AuthView(authManager: authManager)
        }
    }

    private var startupSurface: some View {
        ZStack {
            PawPalBackground()
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [PawPalTheme.orange, PawPalTheme.orangeSoft],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)
                        .shadow(color: PawPalTheme.orange.opacity(0.3), radius: 16, y: 8)
                    Text("🐾")
                        .font(.system(size: 32))
                }

                ProgressView()
                    .tint(PawPalTheme.orange)
            }
        }
    }
}

#Preview {
    ContentView()
}
