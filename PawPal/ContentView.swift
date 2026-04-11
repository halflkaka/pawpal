import SwiftUI

struct ContentView: View {
    @State private var authManager = AuthManager()

    var body: some View {
        Group {
            if authManager.isRestoringSession {
                launchScreen
            } else if authManager.currentUser == nil {
                AuthView(authManager: authManager)
            } else {
                MainTabView(authManager: authManager)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: authManager.isRestoringSession)
        .animation(.easeInOut(duration: 0.2), value: authManager.currentUser?.id)
        .task {
            await authManager.restoreSession()
        }
    }

    private var launchScreen: some View {
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
