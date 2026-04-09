import Foundation
import Supabase

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

struct SupabaseAuthService: AuthService {
    private let client: SupabaseClient

    init() {
        guard let url = URL(string: SupabaseConfig.urlString) else {
            fatalError("Invalid Supabase URL")
        }
        client = SupabaseClient(supabaseURL: url, supabaseKey: SupabaseConfig.anonKey)
    }

    func signIn(email: String, password: String) async throws -> AppUser {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else {
            throw AuthError(message: "Email and password are required.")
        }

        let response = try await client.auth.signIn(email: email, password: password)
        return try requireMappedUser(response.user, fallbackEmail: email)
    }

    func register(email: String, password: String) async throws -> AppUser {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else {
            throw AuthError(message: "Email and password are required.")
        }

        let response = try await client.auth.signUp(email: email, password: password)

        if response.session == nil {
            throw AuthError(message: "This email is already registered. Please sign in instead.")
        }

        return try requireMappedUser(response.user, fallbackEmail: email)
    }

    func restoreSession() async throws -> AppUser? {
        do {
            let session = try await client.auth.session
            return try requireMappedUser(session.user)
        } catch {
            return nil
        }
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    private func requireMappedUser(_ user: User?, fallbackEmail: String? = nil) throws -> AppUser {
        guard let user else {
            throw AuthError(message: "Could not verify your account session. Please try again.")
        }

        let resolvedEmail = user.email ?? fallbackEmail

        return AppUser(
            id: user.id,
            email: resolvedEmail,
            displayName: resolvedEmail?.components(separatedBy: "@").first
        )
    }
}
