import SwiftUI
import UIKit

/// Hashable wrapper appended to a tab's NavigationPath when a push tap
/// arrives via `DeepLinkRouter`. Each case carries the raw UUID; the
/// corresponding `.navigationDestination(for: DeepLinkTarget.self)`
/// handler below resolves the real entity and renders the detail view.
///
/// We don't reuse `RemotePost` / `RemotePet` / `ChatThread` directly
/// because we only have the id at the point of push — fetching the
/// full row before appending would introduce a loading gap where the
/// push feels broken. The resolver view handles the fetch inline so
/// the navigation animation runs immediately.
enum DeepLinkTarget: Hashable {
    case postID(UUID)
    case profileID(UUID)
    case petID(UUID)
    case chatID(UUID)
    case playdateID(UUID)
}

struct MainTabView: View {
    enum AppTab: Hashable {
        case feed
        case discover
        case create
        case chats
        case me
    }

    @State private var selectedTab: AppTab = .feed
    @Bindable var authManager: AuthManager
    @State private var createResetToken = UUID()
    /// Rotated each time the user publishes a post — signals FeedView to reload.
    @State private var feedRefreshID = UUID()

    /// Per-tab navigation paths. We introduced these specifically for
    /// the deep-link entry point — pushing a `DeepLinkTarget` from the
    /// tab bar needs a handle on each tab's stack. The existing tab
    /// views keep using typed `.navigationDestination(for: RemotePost.self)`
    /// handlers inside themselves; the path binding is additive and
    /// doesn't displace that wiring.
    @State private var feedPath = NavigationPath()
    @State private var discoverPath = NavigationPath()
    @State private var chatsPath = NavigationPath()
    @State private var mePath = NavigationPath()

    /// Observes push-tap routing events. When `pendingRoute` flips to
    /// non-nil we switch tabs + append a `DeepLinkTarget` to the right
    /// path, then call `consume()` so the same tap can't re-fire.
    @ObservedObject private var deepLinkRouter = DeepLinkRouter.shared

    /// Drives the foreground refresh of the notification authorization
    /// status — a user who flipped the toggle in iOS Settings while the
    /// app was backgrounded should see the in-app state update when
    /// they return.
    @Environment(\.scenePhase) private var scenePhase

    /// Shared pets cache. We observe it here (rather than only inside
    /// the Me tab) so we can gate the whole app on "user has at least
    /// one pet" — a brand-new account is forced through `OnboardingView`
    /// before the tab bar ever renders.
    @ObservedObject private var petsService = PetsService.shared

    /// Flips true after the first `loadPets` call for the current user
    /// completes. Without this signal a returning user with pets would
    /// flash the onboarding screen for a frame on cold start: the cache
    /// starts empty, `isLoading` is false until the `.task` body runs,
    /// and the gating condition `pets.isEmpty && !isLoading` is
    /// momentarily true. We explicitly wait for the first fetch to
    /// finish before letting the gate fire, so onboarding only shows
    /// when we're confident the empty-pets state is real.
    @State private var hasLoadedPetsAtLeastOnce = false
    /// Tracks which user ID's pets we've loaded. When a different user
    /// signs in (or the current one signs out and another signs in
    /// within the same process), we need to reset
    /// `hasLoadedPetsAtLeastOnce` and re-fetch so the next user's
    /// onboarding gate is evaluated correctly.
    @State private var loadedPetsForUserID: UUID?

    /// The `(id, birthday)` tuples we most recently handed to
    /// `LocalNotificationsService.scheduleBirthdayReminders`. We diff
    /// against this before rescheduling so the `.petDidUpdate`
    /// NotificationCenter broadcast chain from `PetsService` (which
    /// mutates the `pets` array for every avatar upload / accessory
    /// tweak / name edit) doesn't trigger a full cancel-and-reschedule
    /// cycle on every keystroke. Only birthday-relevant changes fire
    /// the scheduler.
    @State private var lastScheduledBirthdayKey: Set<BirthdayKey> = []

    var body: some View {
        Group {
            if shouldShowOnboarding, let user = authManager.currentUser {
                OnboardingView(userID: user.id)
                    .transition(.opacity)
            } else {
                tabContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: shouldShowOnboarding)
        .task(id: authManager.currentUser?.id) {
            await reloadPetsForCurrentUser()
        }
    }

    // MARK: - Gating

    /// True when we're confident the signed-in user has no pets yet and
    /// should be routed through onboarding. Guarded on
    /// `hasLoadedPetsAtLeastOnce` so we don't flash onboarding while the
    /// first fetch is still in flight (see property docstring).
    private var shouldShowOnboarding: Bool {
        guard authManager.currentUser != nil else { return false }
        guard hasLoadedPetsAtLeastOnce else { return false }
        if petsService.isLoading { return false }
        return petsService.pets.isEmpty
    }

    private func reloadPetsForCurrentUser() async {
        guard let user = authManager.currentUser else {
            // Signed out — reset so the next sign-in re-evaluates.
            hasLoadedPetsAtLeastOnce = false
            loadedPetsForUserID = nil
            return
        }

        // Different user than the one we last loaded for — clear the
        // "loaded" flag so onboarding doesn't use stale signal.
        if loadedPetsForUserID != user.id {
            hasLoadedPetsAtLeastOnce = false
        }

        await petsService.loadPets(for: user.id)
        loadedPetsForUserID = user.id
        hasLoadedPetsAtLeastOnce = true
    }

    // MARK: - Tab content

    private var tabContent: some View {
        TabView(selection: $selectedTab) {
            Tab("首页", systemImage: "house.fill", value: .feed) {
                NavigationStack(path: $feedPath) {
                    FeedView(authManager: authManager, postPublishedID: feedRefreshID)
                        .navigationDestination(for: DeepLinkTarget.self) { target in
                            deepLinkDestination(for: target)
                        }
                }
            }
            .accessibilityIdentifier("Home")

            Tab("发现", systemImage: "magnifyingglass", value: .discover) {
                NavigationStack(path: $discoverPath) {
                    DiscoverView(authManager: authManager) {
                        // Empty-state tap routes the user to the Me tab
                        // so they can add a pet via the existing flow there.
                        selectedTab = .me
                    }
                    .navigationDestination(for: DeepLinkTarget.self) { target in
                        deepLinkDestination(for: target)
                    }
                }
            }
            .accessibilityIdentifier("Discover")

            // Use the outline `plus.app` so the glyph reads as a bordered
            // square — matches the design's center "+" CTA.
            Tab("发布", systemImage: "plus.app", value: .create) {
                NavigationStack {
                    CreatePostView(authManager: authManager) {
                        createResetToken = UUID()
                        feedRefreshID = UUID()   // tell FeedView a new post exists
                        selectedTab = .feed
                    }
                    .id(createResetToken)
                }
            }
            .accessibilityIdentifier("Create")

            Tab("聊天", systemImage: "message.fill", value: .chats) {
                NavigationStack(path: $chatsPath) {
                    ChatListView(authManager: authManager)
                        .navigationDestination(for: DeepLinkTarget.self) { target in
                            deepLinkDestination(for: target)
                        }
                }
            }
            // Badge stays off for now — unread counts need a per-thread
            // last-read timestamp that isn't in the MVP schema. Realtime
            // presence + unread lands in a follow-up PR.
            .accessibilityIdentifier("Chats")

            Tab("我的", systemImage: "person.crop.circle.fill", value: .me) {
                NavigationStack(path: $mePath) {
                    if let user = authManager.currentUser {
                        ProfileView(user: user, authManager: authManager) {
                            selectedTab = .create
                        }
                        .navigationDestination(for: DeepLinkTarget.self) { target in
                            deepLinkDestination(for: target)
                        }
                    }
                }
            }
            .accessibilityIdentifier("Pets")
        }
        // Accent now maps to the new brand warm-orange (#FF7A52).
        .tint(PawPalTheme.accent)
        // Let the native liquid-glass material show through on iOS 26.
        // Using `.automatic` keeps the material tab bar with a subtle hairline
        // rule, which matches the design's `rgba(0,0,0,0.08)` top border.
        .toolbarBackground(.automatic, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onChange(of: selectedTab) { oldValue, newValue in
            if oldValue != newValue {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
        // Deep-link dispatch: a push tap writes `DeepLinkRouter.pendingRoute`,
        // we switch tabs + append the target onto the right path, then
        // consume the route so subsequent taps re-fire.
        .onChange(of: deepLinkRouter.pendingRoute) { _, newRoute in
            guard let newRoute else { return }
            handleDeepLink(newRoute)
        }
        // Foreground refresh — if the user flipped the Settings toggle
        // while backgrounded, bring the cached authorization status
        // back in sync on return. Also re-evaluate the birthday-reminder
        // scheduler: a user who granted permission in Settings while
        // backgrounded should get their reminders scheduled on return.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await PushService.shared.refreshAuthorizationStatus()
                    await rescheduleBirthdaysIfChanged(pets: petsService.pets, force: true)
                }
            }
        }
        // Keep birthday reminders in sync with the pets cache. Diff on
        // `(id, birthday)` tuples only so the `.petDidUpdate` broadcast
        // chain (avatar uploads, accessory edits, name tweaks) doesn't
        // spam the scheduler — we only reschedule when the birthday-
        // relevant subset actually changes.
        .onChange(of: petsService.pets) { _, newPets in
            Task { await rescheduleBirthdaysIfChanged(pets: newPets, force: false) }
        }
        // Initial scheduling on `tabContent` mount. Covers the
        // onboarding → tabContent transition path: a user who just
        // added their first pet from OnboardingView has `pets` populated
        // *before* `tabContent` appears, so the `.onChange` above won't
        // fire (no change once it mounts). This `.task` runs once per
        // tabContent appearance and seeds the scheduler with whatever
        // is currently in the cache.
        .task {
            await rescheduleBirthdaysIfChanged(pets: petsService.pets, force: false)
        }
        // Playdate reminder scheduling — mirrors the birthday wiring
        // above but without a diff cache (the set of accepted + future
        // playdates is small enough that a full cancel-and-reschedule
        // pass on every broadcast is trivial). Accept / cancel / decline
        // all fire `.playdateDidChange`, so this observer is the single
        // source of truth for device-schedulable playdate reminders.
        .onReceive(NotificationCenter.default.publisher(for: .playdateDidChange)) { _ in
            Task {
                let now = Date()
                let upcoming = PlaydateService.shared.playdates.values.filter {
                    $0.status == .accepted && $0.scheduled_at > now
                }
                await LocalNotificationsService.shared.schedulePlaydateReminders(for: Array(upcoming))
            }
        }
    }

    // MARK: - Local-notification scheduling

    /// Birthday-relevant fingerprint of the pets cache. We diff this set
    /// against the one we last handed to `LocalNotificationsService`; a
    /// mismatch triggers a reschedule, a match is a no-op.
    private struct BirthdayKey: Hashable {
        let id: UUID
        let birthday: Date?
    }

    /// Schedule / reschedule the birthday reminder batch when the
    /// birthday-relevant pet subset changes. `force` bypasses the diff
    /// and is used on scenePhase → active so a permission flip in
    /// Settings re-runs the scheduler even if pets are unchanged.
    private func rescheduleBirthdaysIfChanged(pets: [RemotePet], force: Bool) async {
        let next = Set(pets.map { BirthdayKey(id: $0.id, birthday: $0.birthday) })
        if !force, next == lastScheduledBirthdayKey { return }
        lastScheduledBirthdayKey = next
        await LocalNotificationsService.shared.scheduleBirthdayReminders(for: pets)
    }

    // MARK: - Deep-link routing

    /// Switches the selected tab, pushes a `DeepLinkTarget` onto its
    /// NavigationPath, then clears the pending route. Same tab-mapping
    /// table as the PM doc: posts → Feed, profiles → Discover (or Me
    /// when it's the current user), chats → Chats.
    private func handleDeepLink(_ route: DeepLinkRouter.Route) {
        switch route {
        case .post(let id):
            selectedTab = .feed
            feedPath.append(DeepLinkTarget.postID(id))
        case .profile(let id):
            if id == authManager.currentUser?.id {
                // Own profile — land on the Me tab. The profile root
                // already renders the signed-in user's view, so no
                // further push is needed.
                selectedTab = .me
            } else {
                selectedTab = .discover
                discoverPath.append(DeepLinkTarget.profileID(id))
            }
        case .pet(let id):
            // Own pet → Me tab's stack; someone else's pet → Discover's.
            // The pet cache is the cheapest authoritative source for
            // ownership; if the pet hasn't loaded yet we default to
            // Discover (the common case for a cross-device / cross-user
            // deep-link) and let the loader handle the fetch.
            if petsService.pets.contains(where: { $0.id == id }) {
                selectedTab = .me
                mePath.append(DeepLinkTarget.petID(id))
            } else {
                selectedTab = .discover
                discoverPath.append(DeepLinkTarget.petID(id))
            }
        case .chat(let id):
            selectedTab = .chats
            chatsPath.append(DeepLinkTarget.chatID(id))
        case .playdate(let id):
            // Playdate deep-links always land on the Feed tab — that's
            // where the pinned playdate cards live, so a tap from a
            // local reminder returns the user to the surface they're
            // used to seeing playdates on.
            selectedTab = .feed
            feedPath.append(DeepLinkTarget.playdateID(id))
        }
        _ = deepLinkRouter.consume()
    }

    /// Destination view for a pushed `DeepLinkTarget`. Does its own
    /// async fetch via the relevant service so the navigation animation
    /// starts immediately (showing a lightweight loading surface)
    /// rather than blocking on the network before navigating.
    @ViewBuilder
    private func deepLinkDestination(for target: DeepLinkTarget) -> some View {
        switch target {
        case .postID(let id):
            DeepLinkPostLoader(postID: id, authManager: authManager)
        case .profileID(let id):
            DeepLinkProfileLoader(userID: id, authManager: authManager)
        case .petID(let id):
            DeepLinkPetLoader(petID: id, authManager: authManager)
        case .chatID(let id):
            DeepLinkChatLoader(conversationID: id, authManager: authManager)
        case .playdateID(let id):
            DeepLinkPlaydateLoader(playdateID: id, authManager: authManager)
        }
    }
}

// MARK: - Deep-link loaders
//
// Each loader fetches the minimum row needed to present the concrete
// detail view (PostDetailView / PetProfileView / ChatDetailView).
// Kept inline with MainTabView since they're only used from
// `deepLinkDestination(for:)`; if a future surface (in-app inbox)
// needs the same, extract to `Views/DeepLink/` at that point.

/// Resolves a post UUID into a `RemotePost` and renders `PostDetailView`.
/// Falls back to an explanatory empty state if the post can't be loaded
/// (deleted, RLS mismatch, network failure) so a stale push doesn't
/// crash the app.
private struct DeepLinkPostLoader: View {
    let postID: UUID
    let authManager: AuthManager

    @StateObject private var postsService = PostsService()
    @State private var post: RemotePost?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let post {
                PostDetailView(
                    post: post,
                    currentUserID: authManager.currentUser?.id,
                    isOwnPost: post.owner_user_id == authManager.currentUser?.id,
                    currentUserDisplayName: authManager.currentProfile?.display_name ?? "用户",
                    currentUsername: authManager.currentProfile?.username,
                    postsService: postsService,
                    authManager: authManager
                )
            } else {
                deepLinkPlaceholder(failed: loadFailed, message: "找不到这条动态")
            }
        }
        .task {
            await load()
        }
    }

    private func load() async {
        do {
            let rows: [RemotePost] = try await SupabaseConfig.client
                .from("posts")
                .select("*, pets(*), profiles!owner_user_id(*), post_images(id, url, position)")
                .eq("id", value: postID.uuidString)
                .limit(1)
                .execute()
                .value
            if let hit = rows.first {
                self.post = hit
            } else {
                self.loadFailed = true
            }
        } catch {
            print("[DeepLink] 加载帖子失败: \(error)")
            self.loadFailed = true
        }
    }
}

/// Resolves a user UUID into that user's primary pet (the PawPal
/// convention is to deep-link profiles to their pet page) and renders
/// `PetProfileView`. Falls back to an empty state on miss.
private struct DeepLinkProfileLoader: View {
    let userID: UUID
    let authManager: AuthManager

    @State private var pet: RemotePet?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let pet {
                PetProfileView(
                    pet: pet,
                    currentUserID: authManager.currentUser?.id,
                    currentUserDisplayName: authManager.currentProfile?.display_name ?? "用户",
                    currentUsername: authManager.currentProfile?.username,
                    authManager: authManager
                )
            } else {
                deepLinkPlaceholder(failed: loadFailed, message: "找不到这位用户")
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let rows: [RemotePet] = try await SupabaseConfig.client
                .from("pets")
                .select()
                .eq("owner_user_id", value: userID.uuidString)
                .order("created_at", ascending: true)
                .limit(1)
                .execute()
                .value
            if let hit = rows.first {
                self.pet = hit
            } else {
                self.loadFailed = true
            }
        } catch {
            print("[DeepLink] 加载用户失败: \(error)")
            self.loadFailed = true
        }
    }
}

/// Resolves a pet UUID into a `RemotePet` and renders `PetProfileView`.
/// Target of the `birthday_today` local notification — tap a 🎂 reminder
/// and land on the celebrating pet's page.
///
/// Prefers the shared `PetsService` cache (covers the "own pet" case
/// without any network), falls back to a Supabase fetch for a pet the
/// current user doesn't own (cross-device link, future playdate push
/// with the partner pet's id). Falls through to an empty-state
/// placeholder on miss so a stale deep-link doesn't crash the app.
private struct DeepLinkPetLoader: View {
    let petID: UUID
    let authManager: AuthManager

    @ObservedObject private var petsService = PetsService.shared
    @State private var pet: RemotePet?
    @State private var loadFailed = false

    init(petID: UUID, authManager: AuthManager) {
        self.petID = petID
        self.authManager = authManager
    }

    var body: some View {
        Group {
            if let pet {
                PetProfileView(
                    pet: pet,
                    currentUserID: authManager.currentUser?.id,
                    currentUserDisplayName: authManager.currentProfile?.display_name ?? "用户",
                    currentUsername: authManager.currentProfile?.username,
                    authManager: authManager
                )
            } else {
                deepLinkPlaceholder(failed: loadFailed, message: "找不到这只毛孩子")
            }
        }
        .task { await load() }
    }

    private func load() async {
        // Cache-first — the owner's own pets are always in
        // `PetsService.shared.pets` after onboarding.
        if let cached = petsService.cachedPet(id: petID) {
            self.pet = cached
            return
        }
        // Cache miss — reuse `PetsService.fetchPet(id:)` so we go
        // through the same `SupabaseConfig.client` pattern the rest of
        // the app uses, rather than instantiating a second client.
        if let fetched = await petsService.fetchPet(id: petID) {
            self.pet = fetched
        } else {
            self.loadFailed = true
        }
    }
}

/// Resolves a conversation UUID into a `ChatThread` (plus the partner
/// profile needed for the header) and renders `ChatDetailView`.
private struct DeepLinkChatLoader: View {
    let conversationID: UUID
    let authManager: AuthManager

    @State private var thread: ChatThread?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let thread {
                ChatDetailView(thread: thread, authManager: authManager)
            } else {
                deepLinkPlaceholder(failed: loadFailed, message: "找不到这段对话")
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let viewerID = authManager.currentUser?.id else {
            loadFailed = true
            return
        }
        do {
            let rows: [RemoteConversation] = try await SupabaseConfig.client
                .from("conversations")
                .select()
                .eq("id", value: conversationID.uuidString)
                .limit(1)
                .execute()
                .value
            guard let conv = rows.first else {
                self.loadFailed = true
                return
            }

            // Best-effort partner profile lookup. Missing profile just
            // falls back to the default "用户" display in ChatThread —
            // we don't want a profile outage to block opening the chat.
            let partnerID = conv.partner(for: viewerID)
            let profiles: [RemoteProfile] = (try? await SupabaseConfig.client
                .from("profiles")
                .select()
                .eq("id", value: partnerID.uuidString)
                .limit(1)
                .execute()
                .value) ?? []

            self.thread = ChatThread(
                conversationID: conv.id,
                partnerID: partnerID,
                partnerProfile: profiles.first,
                lastMessagePreview: conv.last_message_preview,
                lastMessageAt: conv.last_message_at,
                createdAt: conv.created_at
            )
        } catch {
            print("[DeepLink] 加载对话失败: \(error)")
            self.loadFailed = true
        }
    }
}

/// Resolves a playdate UUID into a `RemotePlaydate` and renders
/// `PlaydateDetailView`. Target of `.playdate(...)` routes — triggered
/// both by the APNs `playdate_invited` payload and by the three local
/// `playdate_t_*` reminders (T-24h / T-1h / T+2h).
///
/// Cache-first via `PlaydateService.shared.playdates`; falls back to
/// `PlaydateService.fetch(id:)` if the cache misses (cross-device
/// invite, cold start). Joined pet rows come from the shared
/// `PetsService` cache where possible, with a best-effort fetch for
/// any unresolved id so the avatar strip in the detail view renders
/// with the actual pet photos.
private struct DeepLinkPlaydateLoader: View {
    let playdateID: UUID
    let authManager: AuthManager

    @ObservedObject private var playdateService = PlaydateService.shared
    @ObservedObject private var petsService = PetsService.shared
    @State private var playdate: RemotePlaydate?
    @State private var proposerPet: RemotePet?
    @State private var inviteePet: RemotePet?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let playdate {
                PlaydateDetailView(
                    playdate: playdate,
                    proposerPet: proposerPet,
                    inviteePet: inviteePet,
                    currentUserID: authManager.currentUser?.id,
                    authManager: authManager
                )
            } else {
                deepLinkPlaceholder(failed: loadFailed, message: "找不到这次遛弯")
            }
        }
        .task { await load() }
    }

    private func load() async {
        // Cache-first
        if let cached = playdateService.playdates[playdateID] {
            self.playdate = cached
        } else if let fetched = await playdateService.fetch(id: playdateID) {
            self.playdate = fetched
        } else {
            self.loadFailed = true
            return
        }
        guard let pd = self.playdate else { return }

        // Resolve pets — prefer cache, fall back to per-id fetch.
        if let own = petsService.cachedPet(id: pd.proposer_pet_id) {
            self.proposerPet = own
        } else {
            self.proposerPet = await petsService.fetchPet(id: pd.proposer_pet_id)
        }
        if let own = petsService.cachedPet(id: pd.invitee_pet_id) {
            self.inviteePet = own
        } else {
            self.inviteePet = await petsService.fetchPet(id: pd.invitee_pet_id)
        }
    }
}

/// Shared placeholder for deep-link loader misses. Keeps the three
/// loaders visually consistent.
@ViewBuilder
private func deepLinkPlaceholder(failed: Bool, message: String) -> some View {
    VStack(spacing: PawPalSpacing.md) {
        if failed {
            Text("😿")
                .font(.system(size: 44))
            Text(message)
                .font(PawPalFont.rounded(size: 16, weight: .semibold))
                .foregroundStyle(PawPalTheme.primaryText)
        } else {
            ProgressView()
                .tint(PawPalTheme.accent)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(PawPalBackground())
}
