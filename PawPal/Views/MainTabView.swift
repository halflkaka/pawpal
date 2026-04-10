import SwiftUI

struct MainTabView: View {
    enum AppTab: Hashable {
        case feed
        case discover
        case create
        case chats
        case me
    }

    @State private var selectedTab: AppTab = .feed
    @Bindable var authManager: AuthManager

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Feed", systemImage: "house.fill", value: .feed) {
                NavigationStack {
                    FeedView()
                }
            }

            Tab("Discover", systemImage: "safari.fill", value: .discover) {
                NavigationStack {
                    ContactsView()
                }
            }

            Tab("Post", systemImage: "plus.app.fill", value: .create) {
                NavigationStack {
                    CreatePostView()
                }
            }

            Tab("Chats", systemImage: "message.fill", value: .chats) {
                NavigationStack {
                    ChatListView()
                }
            }
            .badge(2)

            Tab("Me", systemImage: "person.crop.circle.fill", value: .me) {
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
