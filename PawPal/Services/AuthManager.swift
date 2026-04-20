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
        isRestoringSession = true

        // Pre-populate currentUser from cache so the app goes straight to
        // MainTabView on subsequent launches without flashing the auth screen.
        if let idStr = UserDefaults.standard.string(forKey: "pawpal.cachedUserID"),
           let id   = UUID(uuidString: idStr) {
            let email = UserDefaults.standard.string(forKey: "pawpal.cachedUserEmail")
            currentUser = AppUser(
                id: id,
                email: email,
                displayName: email?.components(separatedBy: "@").first
            )
        }
    }

    func restoreSession() async {
        isRestoringSession = true
        errorMessage = nil
        defer { isRestoringSession = false }

        let restored = try? await authService.restoreSession()
        currentUser = restored

        // Keep cache in sync
        if let user = restored {
            UserDefaults.standard.set(user.id.uuidString, forKey: "pawpal.cachedUserID")
            UserDefaults.standard.set(user.email,         forKey: "pawpal.cachedUserEmail")
        } else {
            UserDefaults.standard.removeObject(forKey: "pawpal.cachedUserID")
            UserDefaults.standard.removeObject(forKey: "pawpal.cachedUserEmail")
        }

        await loadCurrentProfileIfNeeded()

        // Re-register the APNs token we stashed on the last session.
        // Safe no-op when no token is cached yet (first launch, or a
        // user who denied the system prompt).
        if let user = currentUser {
            await PushService.shared.registerCurrentToken(for: user.id)
        }
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            currentUser = try await authService.signIn(email: email, password: password)
            await loadCurrentProfileIfNeeded()
            // Push: attach the cached APNs token to this user so they
            // start receiving notifications on this device. The cached
            // token is the one stashed by AppDelegate on the last
            // successful APNs registration — may be nil on a fresh
            // install where the system prompt hasn't been answered yet.
            if let user = currentUser {
                await PushService.shared.registerCurrentToken(for: user.id)
            }
            // Instrumentation: successful password sign-in. Also emit
            // `session_start` so the analytics pipeline counts the
            // post-login presentation as a session without waiting on
            // the next scenePhase flip.
            AnalyticsService.shared.log(.signIn, properties: ["method": "password"])
            AnalyticsService.shared.logSessionStart()
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
            // Same push hookup as signIn — a brand-new account that has
            // already granted the OS prompt (rare, but possible if the
            // user re-registered after signing out) picks up pushes
            // immediately rather than waiting for an app relaunch.
            if let user = currentUser {
                await PushService.shared.registerCurrentToken(for: user.id)
            }
            // Instrumentation: signup counts for D7 cohort bucketing
            // (the retention denominator). Also emit `session_start`
            // so the fresh account's first session is captured.
            AnalyticsService.shared.log(.signUp, properties: ["method": "password"])
            AnalyticsService.shared.logSessionStart()
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

        // Capture the id BEFORE we tear down the session — RLS on
        // `device_tokens` checks `auth.uid() = user_id`, and once
        // `authService.signOut()` returns the Supabase session is gone
        // and `auth.uid()` is null. Any DELETE issued after that point
        // would be silently filtered by RLS and the server would keep
        // pushing to this device after the account was swapped.
        let signOutUserID = currentUser?.id

        Task {
            defer {
                Task { @MainActor in
                    isSigningOut = false
                }
            }

            // Clear the device token BEFORE calling authService.signOut() —
            // see capture above for why order matters.
            if let signOutUserID {
                await PushService.shared.clearToken(for: signOutUserID)
            }

            // Clear every locally scheduled milestone reminder (birthdays
            // today). No dependency on `signOutUserID` — these are
            // device-local reminders, not server state — so this runs
            // unconditionally: a user who revoked app access in Settings
            // should not keep receiving their old pets' birthday pings.
            await LocalNotificationsService.shared.cancelAll()

            do {
                try await authService.signOut()
                await MainActor.run {
                    currentUser = nil
                    currentProfile = nil
                    UserDefaults.standard.removeObject(forKey: "pawpal.cachedUserID")
                    UserDefaults.standard.removeObject(forKey: "pawpal.cachedUserEmail")
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
