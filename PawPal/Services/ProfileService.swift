import Foundation
import Supabase

struct RemoteProfile: Codable, Equatable {
    let id: UUID
    var username: String?
    var display_name: String?
    var bio: String?
    var avatar_url: String?
}

struct ProfileUpsertPayload: Encodable {
    let id: UUID
    let username: String?
    let display_name: String?
    let bio: String?
}

struct ProfileService {
    private let client = SupabaseConfig.client

    func loadProfile(for userID: UUID) async throws -> RemoteProfile? {
        do {
            return try await client
                .from("profiles")
                .select()
                .eq("id", value: userID.uuidString)
                .single()
                .execute()
                .value
        } catch {
            let message = error.localizedDescription.lowercased()
            if message.contains("0 rows") || message.contains("json object requested, multiple (or no) rows returned") {
                return nil
            }
            throw ProfileError(message: "Could not load your account right now.")
        }
    }

    func saveProfile(for userID: UUID, username: String, displayName: String, bio: String) async throws -> RemoteProfile {
        let normalizedUsername = normalizeOptional(username)
        let normalizedDisplayName = normalizeOptional(displayName)
        let normalizedBio = normalizeOptional(bio)

        guard let normalizedUsername, !normalizedUsername.isEmpty else {
            throw ProfileError(message: "Username is required.")
        }

        let payload = ProfileUpsertPayload(
            id: userID,
            username: normalizedUsername.lowercased(),
            display_name: normalizedDisplayName,
            bio: normalizedBio
        )

        do {
            return try await client
                .from("profiles")
                .upsert(payload)
                .select()
                .single()
                .execute()
                .value
        } catch {
            throw mapProfileError(error)
        }
    }

    private func mapProfileError(_ error: Error) -> ProfileError {
        if let profileError = error as? ProfileError {
            return profileError
        }

        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = message.lowercased()

        if normalized.contains("duplicate key") || normalized.contains("profiles_username_key") || normalized.contains("unique") {
            return ProfileError(message: "That username is already taken.")
        }

        if normalized.contains("row-level security") {
            return ProfileError(message: "Could not update your account right now. Please sign in again and retry.")
        }

        if normalized.contains("network") || normalized.contains("internet") || normalized.contains("offline") || normalized.contains("not connected") {
            return ProfileError(message: "You appear to be offline. Please check your connection and try again.")
        }

        return ProfileError(message: message.isEmpty ? "Could not save your account right now. Please try again." : message)
    }

    private func normalizeOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct ProfileError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
