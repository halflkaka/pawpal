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

        do {
            let response = try await client.auth.signIn(email: email, password: password)
            return try requireMappedUser(response.user, fallbackEmail: email)
        } catch {
            throw mapAuthError(error, fallback: "Could not sign you in right now. Please try again.")
        }
    }

    func register(email: String, password: String) async throws -> AppUser {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else {
            throw AuthError(message: "Email and password are required.")
        }

        do {
            let response = try await client.auth.signUp(email: email, password: password)

            if response.session == nil {
                throw AuthError(message: "This email is already registered. Please sign in instead.")
            }

            return try requireMappedUser(response.user, fallbackEmail: email)
        } catch {
            throw mapAuthError(error, fallback: "Could not create your account right now. Please try again.")
        }
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
        do {
            try await client.auth.signOut()
        } catch {
            throw mapAuthError(error, fallback: "Could not sign you out right now. Please try again.")
        }
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

    private func mapAuthError(_ error: Error, fallback: String) -> AuthError {
        if let authError = error as? AuthError {
            return authError
        }

        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = message.lowercased()

        if normalized.contains("invalid login credentials") || normalized.contains("invalid_credentials") {
            return AuthError(message: "That email or password is incorrect.")
        }

        if normalized.contains("email rate limit exceeded") || normalized.contains("over_email_send_rate_limit") || normalized.contains("rate limit") || normalized.contains("too many requests") {
            return AuthError(message: "Too many attempts right now. Please wait a moment and try again.")
        }

        if normalized.contains("user already registered") || normalized.contains("email address is already registered") || normalized.contains("already registered") {
            return AuthError(message: "This email is already registered. Please sign in instead.")
        }

        if normalized.contains("password should be at least") || normalized.contains("weak_password") {
            return AuthError(message: "Your password is too short. Please use a longer password.")
        }

        if normalized.contains("invalid email") || normalized.contains("email_address_invalid") || normalized.contains("unable to validate email address") {
            return AuthError(message: "Please enter a valid email address.")
        }

        if normalized.contains("session") && (normalized.contains("missing") || normalized.contains("expired") || normalized.contains("not found")) {
            return AuthError(message: "Your session expired. Please sign in again.")
        }

        if normalized.contains("network") || normalized.contains("internet") || normalized.contains("offline") || normalized.contains("not connected") {
            return AuthError(message: "You appear to be offline. Please check your connection and try again.")
        }

        if !message.isEmpty {
            return AuthError(message: message)
        }

        return AuthError(message: fallback)
    }
}
