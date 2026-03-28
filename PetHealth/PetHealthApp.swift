import SwiftUI
import SwiftData

@main
struct PetHealthApp: App {
    private let sharedModelContainer: ModelContainer

    init() {
        let schema = Schema([
            StoredPetProfile.self,
            StoredSymptomCheck.self
        ])
        let isUITesting = ProcessInfo.processInfo.arguments.contains("UI_TESTING")
        let config = ModelConfiguration(isStoredInMemoryOnly: isUITesting)

        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create model container: \(error)")
        }

        if ProcessInfo.processInfo.arguments.contains("RESET_SELECTED_PET") {
            UserDefaults.standard.removeObject(forKey: "selectedPetID")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
