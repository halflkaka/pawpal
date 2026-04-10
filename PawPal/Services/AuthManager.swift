import Foundation
import Observation

@MainActor
@Observable
final class AuthManager {
    var currentUser: AppUser?
    var isLoading = false
    var isRestoringSession = false
    var isSigningOut = false
    var errorMessage: String?

    private let authService: AuthService

    init(authService: AuthService = SupabaseAuthService()) {
        self.authService = authService
    }

    func restoreSession() async {
        isRestoringSession = true
        errorMessage = nil
        defer { isRestoringSession = false }

        currentUser = try? await authService.restoreSession()
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

    func clearError() {
        errorMessage = nil
    }

    func signOut() {
        guard !isSigningOut else { return }
        isSigningOut = true
        errorMessage = nil

        Task {
            defer {
                Task { @MainActor in
                    isSigningOut = false
                }
            }

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
