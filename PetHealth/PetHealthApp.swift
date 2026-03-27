import SwiftUI
import SwiftData

@main
struct PetHealthApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [StoredPetProfile.self, StoredSymptomCheck.self])
    }
}
