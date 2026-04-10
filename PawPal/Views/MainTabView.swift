import SwiftUI

struct MainTabView: View {
    enum AppTab: Hashable {
        case chat
        case contacts
        case moments
        case profile
    }

    @State private var selectedTab: AppTab = .moments
    @Bindable var authManager: AuthManager

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ChatListView()
            }
            .tabItem {
                Label("Chat", systemImage: "message.fill")
            }
            .tag(AppTab.chat)

            NavigationStack {
                ContactsView()
            }
            .tabItem {
                Label("Contacts", systemImage: "person.2.fill")
            }
            .tag(AppTab.contacts)

            NavigationStack {
                FeedView()
            }
            .tabItem {
                Label("Moments", systemImage: "camera.on.rectangle")
            }
            .tag(AppTab.moments)

            NavigationStack {
                if let user = authManager.currentUser {
                    ProfileView(user: user, authManager: authManager)
                }
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }
            .tag(AppTab.profile)
        }
    }
}
