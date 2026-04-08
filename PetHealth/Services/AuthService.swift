import Foundation

protocol AuthService {
    func signIn(email: String, password: String) async throws -> AppUser
    func register(email: String, password: String) async throws -> AppUser
    func restoreSession() async throws -> AppUser?
    func signOut() async throws
}

struct AuthError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct PlaceholderAuthService: AuthService {
    func signIn(email: String, password: String) async throws -> AppUser {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else {
            throw AuthError(message: "Email and password are required.")
        }
        return AppUser(id: UUID(), email: email, displayName: email.components(separatedBy: "@").first)
    }

    func register(email: String, password: String) async throws -> AppUser {
        try await signIn(email: email, password: password)
    }

    func restoreSession() async throws -> AppUser? {
        nil
    }

    func signOut() async throws {}
}
