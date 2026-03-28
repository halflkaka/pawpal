import SwiftUI

struct ContentView: View {
    enum AppTab: Hashable {
        case home
        case symptomCheck
        case history
        case pets
        case vets
    }

    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(AppTab.home)

            NavigationStack {
                SymptomCheckView(pet: nil)
            }
            .tabItem {
                Label("Check", systemImage: "stethoscope")
            }
            .tag(AppTab.symptomCheck)

            NavigationStack {
                HistoryView(selectedPetID: nil)
            }
            .tabItem {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .tag(AppTab.history)

            NavigationStack {
                PetProfileView()
            }
            .tabItem {
                Label("Pets", systemImage: "pawprint.fill")
            }
            .tag(AppTab.pets)

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
