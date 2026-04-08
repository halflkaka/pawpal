import SwiftUI

struct ContentView: View {
    @State private var authManager = AuthManager()
    @AppStorage("activePetID") private var activePetID = ""
    @StateObject private var petsService = PetsService()
    @State private var hasCheckedPets = false

    var body: some View {
        Group {
            if authManager.currentUser == nil {
                AuthView(authManager: authManager)
            } else if shouldShowFirstPetSetup, let user = authManager.currentUser {
                FirstPetSetupView(user: user) { pet in
                    activePetID = pet.id.uuidString
                    hasCheckedPets = true
                }
            } else {
                MainTabView(authManager: authManager)
            }
        }
        .task {
            await authManager.restoreSession()
        }
        .task(id: authManager.currentUser?.id) {
            guard let user = authManager.currentUser else {
                hasCheckedPets = false
                return
            }
            await petsService.loadPets(for: user.id)
            if activePetID.isEmpty, let firstPet = petsService.pets.first {
                activePetID = firstPet.id.uuidString
            }
            hasCheckedPets = true
        }
    }

    private var shouldShowFirstPetSetup: Bool {
        guard authManager.currentUser != nil, hasCheckedPets else { return false }
        return petsService.pets.isEmpty
    }
}

#Preview {
    ContentView()
}
