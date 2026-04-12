import SwiftUI

struct ContentView: View {
    @State private var authManager = AuthManager()
    @State private var hasStartedRestore = false

    var body: some View {
        rootContent
            .animation(.easeInOut(duration: 0.2), value: authManager.currentUser?.id)
            .task {
                guard !hasStartedRestore else { return }
                hasStartedRestore = true
                await authManager.restoreSession()
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
