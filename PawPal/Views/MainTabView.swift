import SwiftUI

struct MainTabView: View {
    enum AppTab: Hashable {
        case home
        case explore
        case create
        case chat
        case profile
    }

    @State private var selectedTab: AppTab = .home
    @Bindable var authManager: AuthManager

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                NavigationStack {
                    FeedView()
                }
            }

            Tab("Explore", systemImage: "safari.fill", value: .explore) {
                NavigationStack {
                    ContactsView()
                }
            }

            Tab("Share", systemImage: "plus.app.fill", value: .create) {
                NavigationStack {
                    CreatePostView()
                }
            }

            Tab("Chats", systemImage: "message.fill", value: .chat) {
                NavigationStack {
                    ChatListView()
                }
            }
            .badge(2)

            Tab("Me", systemImage: "pawprint.fill", value: .profile) {
                NavigationStack {
                    if let user = authManager.currentUser {
                        ProfileView(user: user, authManager: authManager)
                    }
                }
            }
        }
        .tint(PawPalTheme.orange)
        .toolbarBackground(PawPalTheme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
