import SwiftUI

struct ContentView: View {
    enum AppTab: Hashable {
        case moments
        case post
        case pets
        case care
        case vets
    }

    @State private var selectedTab: AppTab = .moments

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
