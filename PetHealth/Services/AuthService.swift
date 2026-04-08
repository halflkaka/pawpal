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
        return try await bootstrapUser(from: response.user)
    }

    func register(email: String, password: String) async throws -> AppUser {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else {
            throw AuthError(message: "Email and password are required.")
        }

        let response = try await client.auth.signUp(email: email, password: password)
        return try await bootstrapUser(from: response.user)
    }

    func restoreSession() async throws -> AppUser? {
        let session = try await client.auth.session
        return try await bootstrapUser(from: session.user)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    private func bootstrapUser(from user: User?) async throws -> AppUser {
        guard let user else {
            throw AuthError(message: "Could not load user.")
        }

        let appUser = AppUser(
            id: user.id,
            email: user.email,
            displayName: user.email?.components(separatedBy: "@").first
        )

        try await upsertProfile(for: appUser)
        return appUser
    }

    private func upsertProfile(for user: AppUser) async throws {
        struct ProfilePayload: Encodable {
            let id: UUID
            let username: String?
            let display_name: String?
        }

        let payload = ProfilePayload(
            id: user.id,
            username: user.email?.components(separatedBy: "@").first,
            display_name: user.displayName
        )

        try await client
            .from("profiles")
            .upsert(payload)
            .execute()
    }
}
