import SwiftUI

struct MainTabView: View {
    enum AppTab: Hashable {
        case moments
        case post
        case pets
        case care
        case vets
        case me
    }

    @State private var selectedTab: AppTab = .moments
    @Bindable var authManager: AuthManager

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                FeedView()
            }
            .tabItem {
                Label("Moments", systemImage: "house.fill")
            }
            .tag(AppTab.moments)

            NavigationStack {
                CreatePostView()
            }
            .tabItem {
                Label("Post", systemImage: "square.and.pencil")
            }
            .tag(AppTab.post)

            NavigationStack {
                if let user = authManager.currentUser {
                    RemotePetsView(user: user)
                }
            }
            .tabItem {
                Label("Pets", systemImage: "pawprint.fill")
            }
            .tag(AppTab.pets)

            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Care", systemImage: "stethoscope")
            }
            .tag(AppTab.care)

            NavigationStack {
                VetFinderView()
            }
            .tabItem {
                Label("Vets", systemImage: "cross.case.fill")
            }
            .tag(AppTab.vets)

            NavigationStack {
                if let user = authManager.currentUser {
                    ProfileView(user: user, authManager: authManager)
                }
            }
            .tabItem {
                Label("Me", systemImage: "person.fill")
            }
            .tag(AppTab.me)
        }
    }
}
