import SwiftUI

struct ContentView: View {
    @State private var authManager = AuthManager()

    var body: some View {
        Group {
            if authManager.currentUser == nil {
                AuthView(authManager: authManager)
            } else {
                MainTabView(authManager: authManager)
            }
        }
    }
}

#Preview {
    ContentView()
}
