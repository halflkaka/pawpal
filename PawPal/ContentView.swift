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
        if authManager.isRestoringSession {
            startupSurface
        } else if authManager.currentUser == nil {
            AuthView(authManager: authManager)
        } else {
            MainTabView(authManager: authManager)
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
