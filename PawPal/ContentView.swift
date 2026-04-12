import SwiftUI

struct ContentView: View {
    @State private var authManager = AuthManager()
    @State private var showRestoreOverlay = false
    @State private var didFinishInitialRestore = false

    var body: some View {
        ZStack {
            rootContent

            if showRestoreOverlay {
                restoreOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: authManager.currentUser?.id)
        .animation(.easeInOut(duration: 0.18), value: showRestoreOverlay)
        .task {
            await authManager.restoreSession()
            didFinishInitialRestore = true
        }
        .task(id: authManager.isRestoringSession) {
            if authManager.isRestoringSession {
                try? await Task.sleep(for: .milliseconds(180))
                if authManager.isRestoringSession {
                    showRestoreOverlay = true
                }
            } else {
                showRestoreOverlay = false
            }
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if !didFinishInitialRestore {
            startupPlaceholder
        } else if authManager.currentUser == nil {
            AuthView(authManager: authManager)
        } else {
            MainTabView(authManager: authManager)
        }
    }

    private var startupPlaceholder: some View {
        PawPalBackground()
            .ignoresSafeArea()
    }

    private var restoreOverlay: some View {
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
        .allowsHitTesting(false)
    }
}

#Preview {
    ContentView()
}
