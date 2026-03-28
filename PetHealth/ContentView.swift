import SwiftUI

struct ContentView: View {
    enum AppTab: Hashable {
        case feed
        case post
        case pets
        case care
        case vets
    }

    @State private var selectedTab: AppTab = .feed

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                FeedView()
            }
            .tabItem {
                Label("Feed", systemImage: "house.fill")
            }
            .tag(AppTab.feed)

            NavigationStack {
                CreatePostView()
            }
            .tabItem {
                Label("Post", systemImage: "plus.app.fill")
            }
            .tag(AppTab.post)

            NavigationStack {
                PetProfileView()
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
        }
    }
}

#Preview {
    ContentView()
}
