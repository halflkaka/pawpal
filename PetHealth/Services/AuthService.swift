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
        return mapUser(response.user)
    }

    func register(email: String, password: String) async throws -> AppUser {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else {
            throw AuthError(message: "Email and password are required.")
        }

        let response = try await client.auth.signUp(email: email, password: password)
        return mapUser(response.user)
    }

    func restoreSession() async throws -> AppUser? {
        do {
            let session = try await client.auth.session
            return mapUser(session.user)
        } catch {
            return nil
        }
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    private func mapUser(_ user: User?) -> AppUser {
        AppUser(
            id: user?.id ?? UUID(),
            email: user?.email,
            displayName: user?.email?.components(separatedBy: "@").first
        )
    }
}
