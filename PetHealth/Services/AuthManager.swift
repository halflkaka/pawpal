import Foundation
import Observation

@MainActor
@Observable
final class AuthManager {
    var currentUser: AppUser?
    var isLoading = false
    var errorMessage: String?

    private let authService: AuthService

    init(authService: AuthService = PlaceholderAuthService()) {
        self.authService = authService
    }

    func restoreSession() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            currentUser = try await authService.restoreSession()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            currentUser = try await authService.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func register(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            currentUser = try await authService.register(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        Task {
            do {
                try await authService.signOut()
                await MainActor.run {
                    currentUser = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
