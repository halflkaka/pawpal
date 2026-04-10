import SwiftUI
import SwiftData

@main
struct PetHealthApp: App {
    private let sharedModelContainer: ModelContainer

    init() {
        let schema = Schema([StoredPost.self])
        let isUITesting = ProcessInfo.processInfo.arguments.contains("UI_TESTING")
        let config = ModelConfiguration(isStoredInMemoryOnly: isUITesting)

        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
