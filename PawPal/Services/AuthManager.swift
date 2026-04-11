import Foundation
import Observation

@MainActor
@Observable
final class AuthManager {
    var currentUser: AppUser?
    var currentProfile: RemoteProfile?
    var isLoading = false
    var isRestoringSession = false
    var isSigningOut = false
    var errorMessage: String?

    private let authService: AuthService
    private let profileService = ProfileService()

    init(authService: AuthService = SupabaseAuthService()) {
        self.authService = authService
        // Start true so ContentView shows the launch screen on first render
        // instead of briefly flashing AuthView before restoreSession() runs.
        isRestoringSession = true
    }

    func restoreSession() async {
        isRestoringSession = true
        errorMessage = nil
        defer { isRestoringSession = false }

        currentUser = try? await authService.restoreSession()
        await loadCurrentProfileIfNeeded()
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            currentUser = try await authService.signIn(email: email, password: password)
            await loadCurrentProfileIfNeeded()
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
            await loadCurrentProfileIfNeeded()
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
                    currentProfile = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func refreshCurrentProfile() async {
        await loadCurrentProfileIfNeeded(force: true)
    }

    private func loadCurrentProfileIfNeeded(force: Bool = false) async {
        guard let user = currentUser else {
            currentProfile = nil
            return
        }
        if currentProfile != nil && !force { return }
        currentProfile = try? await profileService.loadProfile(for: user.id)
    }
}
