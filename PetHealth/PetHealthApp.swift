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

        func makeContainer() throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: [config])
        }

        do {
            sharedModelContainer = try makeContainer()
        } catch {
            if !isUITesting {
                clearLocalSwiftDataStore()
            }

            do {
                sharedModelContainer = try makeContainer()
            } catch {
                fatalError("Failed to create model container: \(error)")
            }
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

private func clearLocalSwiftDataStore() {
    let fileManager = FileManager.default
    guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        return
    }

    let defaultStore = appSupport.appendingPathComponent("default.store")
    let defaultStoreWal = appSupport.appendingPathComponent("default.store-wal")
    let defaultStoreShm = appSupport.appendingPathComponent("default.store-shm")

    [defaultStore, defaultStoreWal, defaultStoreShm].forEach { url in
        try? fileManager.removeItem(at: url)
    }
}
