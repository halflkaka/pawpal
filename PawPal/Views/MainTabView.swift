import SwiftUI
import UIKit

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
            Tab("首页", systemImage: "house.fill", value: .feed) {
                NavigationStack {
                    FeedView(authManager: authManager)
                }
            }
            .accessibilityIdentifier("Home")

            Tab("发现", systemImage: "safari.fill", value: .discover) {
                NavigationStack {
                    ContactsView()
                }
            }
            .accessibilityIdentifier("Discover")

            Tab("发布", systemImage: "plus.app.fill", value: .create) {
                NavigationStack {
                    CreatePostView(authManager: authManager)
                }
            }
            .accessibilityIdentifier("Create")

            Tab("聊天", systemImage: "message.fill", value: .chats) {
                NavigationStack {
                    ChatListView()
                }
            }
            .badge(2)
            .accessibilityIdentifier("Chats")

            Tab("我的", systemImage: "person.crop.circle.fill", value: .me) {
                NavigationStack {
                    if let user = authManager.currentUser {
                        ProfileView(user: user, authManager: authManager)
                    }
                }
            }
            .accessibilityIdentifier("Pets")
        }
        .tint(PawPalTheme.orange)
        .toolbarBackground(PawPalTheme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onChange(of: selectedTab) { oldValue, newValue in
            if oldValue != newValue {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }
}
