import Foundation
import Observation

@MainActor
@Observable
final class AuthManager {
    var currentUser: AppUser?
    var isLoading = false
    var errorMessage: String?

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Placeholder auth scaffold. Supabase SDK integration is the next step.
        // For now this establishes the app structure for a real account flow.
        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty {
            errorMessage = "Email and password are required."
            return
        }

        currentUser = AppUser(id: UUID(), email: email, displayName: email.components(separatedBy: "@").first)
    }

    func register(email: String, password: String) async {
        await signIn(email: email, password: password)
    }

    func signOut() {
        currentUser = nil
    }
}
