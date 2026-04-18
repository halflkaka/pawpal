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
    @State private var createResetToken = UUID()
    /// Rotated each time the user publishes a post — signals FeedView to reload.
    @State private var feedRefreshID = UUID()

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("首页", systemImage: "house.fill", value: .feed) {
                NavigationStack {
                    FeedView(authManager: authManager, postPublishedID: feedRefreshID)
                }
            }
            .accessibilityIdentifier("Home")

            Tab("发现", systemImage: "magnifyingglass", value: .discover) {
                NavigationStack {
                    ContactsView()
                }
            }
            .accessibilityIdentifier("Discover")

            // Use the outline `plus.app` so the glyph reads as a bordered
            // square — matches the design's center "+" CTA.
            Tab("发布", systemImage: "plus.app", value: .create) {
                NavigationStack {
                    CreatePostView(authManager: authManager) {
                        createResetToken = UUID()
                        feedRefreshID = UUID()   // tell FeedView a new post exists
                        selectedTab = .feed
                    }
                    .id(createResetToken)
                }
            }
            .accessibilityIdentifier("Create")

            Tab("聊天", systemImage: "message.fill", value: .chats) {
                NavigationStack {
                    ChatListView(authManager: authManager)
                }
            }
            // Badge stays off for now — unread counts need a per-thread
            // last-read timestamp that isn't in the MVP schema. Realtime
            // presence + unread lands in a follow-up PR.
            .accessibilityIdentifier("Chats")

            Tab("我的", systemImage: "person.crop.circle.fill", value: .me) {
                NavigationStack {
                    if let user = authManager.currentUser {
                        ProfileView(user: user, authManager: authManager) {
                            selectedTab = .create
                        }
                    }
                }
            }
            .accessibilityIdentifier("Pets")
        }
        // Accent now maps to the new brand warm-orange (#FF7A52).
        .tint(PawPalTheme.accent)
        // Let the native liquid-glass material show through on iOS 26.
        // Using `.automatic` keeps the material tab bar with a subtle hairline
        // rule, which matches the design's `rgba(0,0,0,0.08)` top border.
        .toolbarBackground(.automatic, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onChange(of: selectedTab) { oldValue, newValue in
            if oldValue != newValue {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }
}
