import SwiftUI
import PhotosUI

struct PetProfileView: View {
    // Converted from `let` to `@State` because the owner can now edit the
    // avatar from within this screen. When the avatar upload succeeds we
    // refresh `pet.avatar_url` locally so the new photo renders without a
    // round-trip reload of the parent list.
    @State private var pet: RemotePet
    let currentUserID: UUID?
    let currentUserDisplayName: String
    let currentUsername: String?
    /// Required to push a `ChatDetailView` when the visitor taps
    /// "发消息". Optional because some call sites (e.g. `PostDetailView`)
    /// don't receive the auth manager — those screens just won't show
    /// the message button. The owner flow never needs this either
    /// (owners don't DM their own pet).
    var authManager: AuthManager?

    @StateObject private var postsService = PostsService()
    // Shared with `ProfileView` so optimistic accessory writes there (the
    // owner taps 🎩 on their own profile) propagate here without a
    // Supabase round-trip. Two separate `@StateObject` instances used to
    // cause a read-after-write race where `refreshPetIfNeeded` would hit
    // the DB before the write from `ProfileView` landed — the virtual pet
    // would appear bare-headed on first appear, then quietly pick up the
    // hat on a subsequent refresh. See `PetsService.shared` docstring.
    @ObservedObject private var petsService = PetsService.shared
    /// Shared with `ProfileView` for tap-count sync and persisted
    /// feed/pet/play stat bumps. See `VirtualPetStateStore` docs for
    /// why both screens observe the same store.
    @ObservedObject private var petStateStore = VirtualPetStateStore.shared

    // Avatar editing state — mirrors the pattern used in `ProfileView`'s
    // account / add-pet sheets so the three avatar pickers in the app
    // behave consistently.
    @State private var pickedAvatarItem: PhotosPickerItem?
    @State private var pickedAvatarPreview: Image?
    @State private var isUploadingAvatar = false
    @State private var avatarErrorMessage: String?

    // Engagement (visits + boops) — CHANGELOG #38. Counts are loaded
    // from Supabase on appear; the boop total gets optimistic local
    // increments while a background task debounces the real write.
    //
    // `visitCount` reads `COUNT(*) from pet_visits` where each row is a
    // unique (pet, viewer, day) tuple — so a visitor returning on a new
    // day bumps the count.
    //
    // `boopCount` reflects the server's `pets.boop_count` plus any
    // taps that haven't been flushed yet. The display value is the
    // sum: `displayBoopCount = serverBoopCount + pendingBoopDelta`.
    @State private var visitCount: Int = 0
    @State private var serverBoopCount: Int = 0
    @State private var pendingBoopDelta: Int = 0
    @State private var boopFlushTask: Task<Void, Never>?

    /// Debounce window — after the last tap, wait this long before
    /// flushing the accumulated delta to the server. Short enough that
    /// a visitor who reads a profile and leaves sees their count
    /// persisted; long enough that a quick burst of 8-10 rapid taps
    /// becomes one RPC call.
    private let boopFlushDelay: TimeInterval = 1.8

    // Chat entry point state. When the visitor taps "发消息" on a
    // non-owner profile we resolve the owner's profile (for the chat
    // header avatar + handle), call `ChatService.startConversation` to
    // find-or-create the thread, then push `ChatDetailView`. The whole
    // flow is gated by `authManager` being non-nil since the detail
    // view needs it for the current-user id.
    @State private var isStartingChat = false
    @State private var pendingChatThread: ChatThread?
    @State private var chatErrorMessage: String?

    init(
        pet: RemotePet,
        currentUserID: UUID? = nil,
        currentUserDisplayName: String = "用户",
        currentUsername: String? = nil,
        authManager: AuthManager? = nil
    ) {
        _pet = State(initialValue: pet)
        self.currentUserID = currentUserID
        self.currentUserDisplayName = currentUserDisplayName
        self.currentUsername = currentUsername
        self.authManager = authManager
    }

    /// Whether the viewing user owns this pet — drives the edit affordance
    /// on the avatar. We intentionally don't expose edit on other fields
    /// here (name/breed/etc.) — that flow lives on `ProfileView` via the
    /// dedicated edit sheet.
    private var canEdit: Bool {
        guard let currentUserID else { return false }
        return pet.owner_user_id == currentUserID
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                petHeader
                Divider()
                postsGrid
            }
        }
        .scrollIndicators(.hidden)
        .background(PawPalBackground())
        .navigationTitle(pet.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: RemotePost.self) { post in
            PostDetailView(
                post: post,
                currentUserID: currentUserID,
                isOwnPost: post.owner_user_id == currentUserID,
                currentUserDisplayName: currentUserDisplayName,
                currentUsername: currentUsername,
                postsService: postsService,
                authManager: authManager
            )
        }
        // Chat push — populated by `startChatWithOwner()` after
        // `ChatService.startConversation` resolves. Using `item:` so
        // the push only happens once the thread is ready, avoiding the
        // flash-and-pop you'd get if we toggled an `isPresented` bool
        // before the conversation id arrived.
        .navigationDestination(item: $pendingChatThread) { thread in
            if let authManager {
                ChatDetailView(thread: thread, authManager: authManager)
            }
        }
        .refreshable {
            // Pull the posts and the engagement counts together so the
            // header stats stay in sync with the feed. Serial rather
            // than parallel — these are all cheap and running them in
            // order keeps the refreshable closure simple.
            await postsService.loadPetPosts(for: pet.id)
            await loadEngagementCounts()
            await refreshPetIfNeeded()
        }
        .task {
            await postsService.loadPetPosts(for: pet.id)
            await loadEngagementCounts()
            await refreshPetIfNeeded()
            await recordVisitIfNeeded()
        }
        .onChange(of: pickedAvatarItem) { _, item in
            guard let item else { return }
            Task { await handlePickedAvatar(item) }
        }
        .onDisappear {
            // Guarantee any buffered boops land even if the debounce
            // window hasn't elapsed. Without this, a visitor who taps
            // 3× then immediately navigates away would lose those taps.
            flushPendingBoops()
        }
    }

    // MARK: - Avatar

    private var petAvatar: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [PawPalTheme.orange.opacity(0.28), PawPalTheme.cardSoft],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 96, height: 96)
                .shadow(color: PawPalTheme.orange.opacity(0.22), radius: 18, y: 8)

            // Priority: the user's just-picked preview (while we wait on
            // the upload) → remote avatar URL → species emoji fallback.
            // Showing the preview immediately avoids a visible lag between
            // "I picked a photo" and "the photo is my avatar".
            if let pickedAvatarPreview {
                pickedAvatarPreview
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())
            } else if let urlString = pet.avatar_url, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                    case .failure:
                        Text(speciesEmoji(for: pet.species ?? ""))
                            .font(.system(size: 48))
                    default:
                        ProgressView()
                            .frame(width: 96, height: 96)
                    }
                }
            } else {
                Text(speciesEmoji(for: pet.species ?? ""))
                    .font(.system(size: 48))
            }

            // A subtle dimming overlay + spinner while the upload is in
            // flight. Keeps the UI honest about the pending state without
            // blocking interaction elsewhere on the screen.
            if isUploadingAvatar {
                Circle()
                    .fill(Color.black.opacity(0.28))
                    .frame(width: 96, height: 96)
                ProgressView()
                    .tint(.white)
            }
        }
        .overlay(Circle().stroke(PawPalTheme.orange.opacity(0.35), lineWidth: 3))
    }

    /// Wraps the avatar in a `PhotosPicker` and overlays a small camera
    /// badge — but only for the pet's owner. Non-owners see a plain
    /// avatar with no edit affordance.
    @ViewBuilder
    private var avatarWithEditAffordance: some View {
        if canEdit {
            PhotosPicker(
                selection: $pickedAvatarItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                ZStack(alignment: .bottomTrailing) {
                    petAvatar
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(PawPalTheme.orange, in: Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .offset(x: 4, y: 4)
                }
            }
            .buttonStyle(.plain)
            .disabled(isUploadingAvatar)
        } else {
            petAvatar
        }
    }

    // MARK: - Header

    private var petHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Avatar — explicitly centered despite leading VStack
            avatarWithEditAffordance
                .frame(maxWidth: .infinity, alignment: .center)

            if canEdit {
                Text("点击头像更换照片")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PawPalTheme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if let avatarErrorMessage {
                Text(avatarErrorMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            // "发消息" button — only shown to non-owner visitors who have
            // an authenticated session. The owner doesn't DM their own
            // pet; unauthenticated callers (PostDetailView path without
            // an authManager) don't get the affordance either because
            // `ChatDetailView` requires the binding.
            if !canEdit,
               currentUserID != nil,
               authManager != nil,
               pet.owner_user_id != currentUserID {
                messageOwnerButton
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if let chatErrorMessage {
                Text(chatErrorMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            // Tag pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let species = pet.species, !species.isEmpty {
                        PawPalPill(text: speciesDisplayName(species), systemImage: "pawprint.fill", tint: PawPalTheme.orange)
                    }
                    if let breed = pet.breed, !breed.isEmpty {
                        PawPalPill(text: breed, systemImage: nil, tint: PawPalTheme.secondaryText)
                    }
                    if let age = pet.age, !age.isEmpty {
                        PawPalPill(text: withUnit(age, defaultUnit: "岁"), systemImage: "calendar", tint: PawPalTheme.tertiaryText)
                    }
                    if let sex = pet.sex, !sex.isEmpty {
                        PawPalPill(text: localizedSex(sex), systemImage: nil, tint: PawPalTheme.tertiaryText)
                    }
                    if let weight = pet.weight, !weight.isEmpty {
                        PawPalPill(text: withUnit(weight, defaultUnit: "公斤"), systemImage: "scalemass", tint: PawPalTheme.tertiaryText)
                    }
                }
            }

            // City
            if let city = pet.home_city, !city.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 11))
                    Text(city)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(PawPalTheme.tertiaryText)
            }

            // Bio
            if let bio = pet.bio, !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(bio)
                    .font(.system(size: 14))
                    .foregroundStyle(PawPalTheme.secondaryText)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Virtual pet stage — the same interactive stage from
            // `ProfileView` (feed / pet / play, stats bars, thought
            // bubble, tap-to-boop). Seeded from the pet's own posts via
            // `PetStats.make` so a well-loved pet lands near 100% mood.
            // `.id(pet.id)` resets the internal animation/accessory state
            // if the user navigates from one pet to another.
            //
            // `onBoop` is wired only when the viewer is *not* the owner.
            // The owner booping their own pet doesn't contribute to the
            // shared counter (same principle as skipping self-visits).
            // Type annotation avoids a ternary-inference warning where
            // `nil` and the closure have no obvious common type.
            // Compute once and reuse for both the seed `state:` and the
            // external stat bindings so they're guaranteed to read the
            // same (posts + time) snapshot — otherwise a partial render
            // between `posts` load and `now` advancement could briefly
            // disagree with itself.
            let vpState = pet.virtualPetState(
                stats: PetStats.make(from: postsService.petPosts),
                posts: postsService.petPosts
            )
            // Prefer the persisted `pet_state` snapshot when we have one
            // so owner-driven feed/pet/play bumps from either screen are
            // reflected here. Non-owners still see the latest values —
            // the SELECT policy on `pet_state` is public.
            let persisted = petStateStore.state(for: pet.id)
            let displayMood   = persisted?.mood   ?? vpState.mood
            let displayHunger = persisted?.hunger ?? vpState.hunger
            let displayEnergy = persisted?.energy ?? vpState.energy
            VirtualPetView(
                state: vpState,
                // Binding through the shared store keeps tap counters and
                // stat bars in sync with `ProfileView`.
                petID: pet.id,
                // Parent-owned accessory so that when the owner dresses
                // up the pet in `ProfileView` (which shares
                // `PetsService.shared`), the cache update flows back here
                // via `pet.accessory` and `VirtualPetView`'s `.onChange`
                // animates the hat on without re-initialising the view.
                // This is what finally fixes the "virtual pet is reset
                // every time I go back to pet profile" bug — the view
                // keeps its internal thought / tap / animation state,
                // and only the accessory animates between values.
                externalAccessory: DogAvatar.Accessory(rawValue: pet.accessory ?? "none") ?? DogAvatar.Accessory.none,
                // Stats now come from the persisted snapshot when we have
                // one, so owner taps on 喂食 / 玩耍 persist and reflect
                // here too. Falling back to the time-derived baseline
                // means a pet with no stat history reads sensibly on
                // first view without needing a write first.
                externalMood: displayMood,
                externalHunger: displayHunger,
                externalEnergy: displayEnergy,
                onAccessoryChanged: canEdit ? persistAccessory : nil,
                onBoop: virtualPetBoopHandler,
                // Only the owner can mutate `pet_state` (RLS enforces it
                // server-side). Passing nil for visitors means their
                // 喂食 tap still fires the reaction emoji + thought
                // bubble but doesn't try to move the bar.
                onAction: canEdit
                    ? { action in
                        Task {
                            await petStateStore.applyAction(
                                action,
                                petID: pet.id,
                                baseline: (vpState.mood, vpState.hunger, vpState.energy)
                            )
                        }
                    }
                    : nil
            )
            .id(pet.id)  // reset only when the pet itself changes, not on accessory tweaks
            .task(id: pet.id) {
                // Same lazy-load pattern as ProfileView so whichever
                // screen appears first primes the cache; the other
                // short-circuits the fetch via `loadIfNeeded`'s maxAge.
                await petStateStore.loadIfNeeded(petID: pet.id)
            }

            // Engagement stats — three columns so visitors see the pet's
            // social footprint at a glance: how many posts they've made,
            // how many unique-day visits the profile has had, and how
            // many times anyone has booped them.
            HStack(spacing: 0) {
                statCell(value: formatCount(postsService.petPosts.count), label: "帖子")
                statDivider()
                statCell(value: formatCount(visitCount), label: "访客")
                statDivider()
                statCell(value: formatCount(displayBoopCount), label: "摸摸")
            }
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 28)
    }

    // MARK: - Chat entry point

    /// Warm-accent pill button that kicks off (or re-opens) a DM with
    /// the pet's owner. Disabled while `startChatWithOwner` is in
    /// flight so a second tap while the `startConversation` round-trip
    /// is pending can't spawn a parallel push.
    private var messageOwnerButton: some View {
        Button {
            Task { await startChatWithOwner() }
        } label: {
            HStack(spacing: 6) {
                if isStartingChat {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(isStartingChat ? "正在打开…" : "给主人发消息")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(PawPalTheme.accent, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isStartingChat)
    }

    /// Starts or re-opens a DM with the pet's owner, then sets
    /// `pendingChatThread` to trigger the navigation destination push.
    /// Looks up the owner's profile in parallel with the conversation
    /// create so the chat header avatar + handle render immediately
    /// rather than blanking until the detail view's own fetch resolves.
    private func startChatWithOwner() async {
        guard let viewerID = currentUserID else { return }
        guard viewerID != pet.owner_user_id else { return }
        guard authManager != nil else { return }
        isStartingChat = true
        chatErrorMessage = nil
        defer { isStartingChat = false }

        async let convoTask = ChatService.shared.startConversation(
            userA: viewerID,
            userB: pet.owner_user_id
        )
        async let ownerProfileTask = ProfileService().loadProfile(for: pet.owner_user_id)
        let conversationID = await convoTask
        let ownerProfile = try? await ownerProfileTask

        guard let conversationID else {
            chatErrorMessage = "无法创建聊天,请稍后再试"
            return
        }
        pendingChatThread = ChatThread(
            conversationID: conversationID,
            partnerID: pet.owner_user_id,
            partnerProfile: ownerProfile,
            lastMessagePreview: nil,
            lastMessageAt: nil,
            createdAt: Date()
        )
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Engagement helpers (visits + boops)

    /// The closure passed to `VirtualPetView.onBoop`. Returns nil for
    /// the owner (their own boops don't bump the public counter), and
    /// a real handler for anyone else.
    private var virtualPetBoopHandler: (() -> Void)? {
        canEdit ? nil : { handleBoop() }
    }

    /// Persist the virtual pet's chosen accessory to the `pets` table so
    /// a bow / hat / glasses survives reloads. Only wired for the owner
    /// (non-owners can't edit anyway — the accessory chips are
    /// tap-enabled regardless, but the RLS policy on `pets` rejects the
    /// write so visitors dressing up someone else's pet would see a
    /// short-lived local change that wouldn't persist anyway). Updates
    /// the local `pet.accessory` so the next `.id(pet.id)` reset of
    /// `VirtualPetView` (e.g. after avatar edit) still shows the saved
    /// accessory instead of snapping back to `.none`.
    private func persistAccessory(_ accessory: DogAvatar.Accessory) {
        guard let currentUserID, canEdit else { return }
        let raw = accessory.rawValue
        pet.accessory = raw
        Task {
            await petsService.updatePetAccessory(
                petID: pet.id,
                ownerID: currentUserID,
                accessory: raw
            )
        }
    }

    /// Optimistic boop count shown in the stats card: the server's
    /// last-known value plus anything we've buffered locally but not
    /// yet flushed.
    private var displayBoopCount: Int {
        serverBoopCount + pendingBoopDelta
    }

    /// Formats large counts as "1.2k", etc., so the three-column stats
    /// card stays readable even for pets with thousands of boops.
    private func formatCount(_ value: Int) -> String {
        if value >= 10_000 {
            let k = Double(value) / 1_000
            return String(format: "%.1fk", k)
        }
        if value >= 1_000 {
            let k = Double(value) / 1_000
            return String(format: "%.1fk", k)
        }
        return "\(value)"
    }

    /// A single cell in the three-column engagement stats row.
    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.25), value: value)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Thin vertical divider between stat cells — matches the hairline
    /// style used elsewhere so the stats card reads as a single card
    /// rather than three disconnected tiles.
    private func statDivider() -> some View {
        Rectangle()
            .fill(PawPalTheme.hairline)
            .frame(width: 0.5, height: 24)
    }

    /// Re-read this pet so cross-view edits become visible here on every
    /// (re-)appear. Two sources are consulted:
    ///
    ///   1. The shared `PetsService` cache (synchronous) — any optimistic
    ///      write from another screen is already there, so this is at
    ///      least as fresh as a DB round-trip for the owner's own pets.
    ///   2. Supabase (async) — catches cross-device changes and refreshes
    ///      counters (boop_count, avatar_url).
    ///
    /// Merge rule: if the cache has a non-nil accessory and the DB
    /// returned nil/"none", prefer the cache value. Protects against the
    /// rare race where the fetch beats the optimistic write's replication.
    ///
    /// Historical note: this method used to bump a `petReloadSeed` that
    /// was mixed into `VirtualPetView.id` to force re-init on accessory
    /// changes. That approach had two problems — bumping unconditionally
    /// reset the virtual pet's internal state (thoughts / tap count /
    /// animation phase) on every pop-back, and bumping conditionally
    /// missed edge cases. Both have been replaced by `VirtualPetView`'s
    /// `externalAccessory` input + `.onChange` sync, which picks up
    /// cache-driven accessory changes without re-initialising the view.
    /// Pushing the reassignment to `@State var pet` is still enough here
    /// because `externalAccessory` is bound to `pet.accessory` and
    /// SwiftUI propagates the new value through.
    private func refreshPetIfNeeded() async {
        // 1. Cache-first: if PetsService has a row for this pet, use it.
        if let cached = petsService.cachedPet(id: pet.id) {
            pet = cached
        }

        // 2. DB fetch: refresh counters and cross-device changes. Falls
        //    through on failure — we already seeded from cache (or nav arg).
        guard let fresh = await petsService.fetchPet(id: pet.id) else { return }
        var merged = fresh
        // Guard against the rare race where fetch beat the optimistic
        // write to Supabase: if cache has a non-nil accessory and DB
        // came back empty, prefer cache.
        if let cachedAccessory = petsService.cachedPet(id: pet.id)?.accessory,
           !cachedAccessory.isEmpty,
           normalizedAccessory(merged.accessory) == "none",
           normalizedAccessory(cachedAccessory) != "none" {
            merged.accessory = cachedAccessory
        }
        pet = merged
    }

    /// Normalises the raw accessory string so nil / empty / "none" all
    /// compare equal — the DB stores "none" explicitly for rows written
    /// after migration 014, but older rows and optimistic in-flight
    /// writes may have nil. Treating them as equal prevents a rewrite
    /// loop where the merge logic keeps flipping between nil and "none".
    private func normalizedAccessory(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "none" : trimmed
    }

    /// Loads the two engagement totals in parallel. Called on .task and
    /// on pull-to-refresh.
    private func loadEngagementCounts() async {
        async let visits = petsService.fetchVisitCount(petID: pet.id)
        async let boops = petsService.fetchBoopCount(petID: pet.id)
        let (v, b) = await (visits, boops)
        visitCount = v
        // Reconcile: the server number is authoritative, but any taps
        // that happened while the fetch was in flight should still be
        // reflected in the display. We keep `pendingBoopDelta` intact.
        serverBoopCount = b
    }

    /// Records a unique-per-day visit. Skipped silently when the viewer
    /// is the pet's owner (same "don't count self-views" rule the user
    /// picked). Non-authenticated users also don't contribute — we have
    /// no user_id to attribute the visit to.
    private func recordVisitIfNeeded() async {
        guard let currentUserID else { return }
        guard currentUserID != pet.owner_user_id else { return }

        await petsService.recordVisit(
            petID: pet.id,
            viewerUserID: currentUserID,
            ownerID: pet.owner_user_id
        )

        // Re-fetch so the stats card reflects our own visit immediately
        // (if this was our first visit today). We could increment
        // locally, but the round-trip is cheap and the exact count
        // matters less than staying truthful.
        visitCount = await petsService.fetchVisitCount(petID: pet.id)
    }

    /// Called every time `VirtualPetView` fires its `onBoop` callback
    /// (i.e. every tap on the pet character). We increment a local
    /// delta — the stats card reflects the new number immediately —
    /// and arm a debounce timer that flushes the accumulated delta to
    /// the server after `boopFlushDelay` seconds of silence.
    private func handleBoop() {
        pendingBoopDelta += 1
        scheduleBoopFlush()
    }

    /// Arms (or re-arms) the debounced flush. Cancelling the previous
    /// task is important — without it, every tap would schedule its
    /// own flush and we'd make N RPCs instead of one.
    ///
    /// `@MainActor` inside the Task closure: the task mutates `@State`
    /// via `flush()`, so it must run on the main actor. Inheriting
    /// from the call-site isolation would be fragile — handleBoop() is
    /// called from a closure passed into `VirtualPetView`, and the
    /// Swift 5.9 inheritance rules depend on the caller's isolation.
    /// Pinning the Task makes the intent explicit.
    private func scheduleBoopFlush() {
        boopFlushTask?.cancel()
        let delay = boopFlushDelay
        boopFlushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if Task.isCancelled { return }
            await flush()
        }
    }

    /// Flushes the pending boop delta immediately (not waiting for the
    /// debounce). Called from `.onDisappear` so the last few taps
    /// before navigation survive.
    private func flushPendingBoops() {
        boopFlushTask?.cancel()
        boopFlushTask = nil
        guard pendingBoopDelta > 0 else { return }
        let delta = pendingBoopDelta
        pendingBoopDelta = 0
        Task { @MainActor in
            if let newServerCount = await petsService.incrementBoopCount(petID: pet.id, by: delta) {
                serverBoopCount = newServerCount
            } else {
                // Rollback the optimistic increment so the UI doesn't
                // show a count we never persisted. We add back to
                // `pendingBoopDelta` (not `serverBoopCount`) in case the
                // next flush succeeds.
                pendingBoopDelta += delta
            }
        }
    }

    /// Runs the actual flush inside the debounced task. Kept on
    /// MainActor via the Task's isolation in `scheduleBoopFlush`.
    @MainActor
    private func flush() async {
        guard pendingBoopDelta > 0 else { return }
        let delta = pendingBoopDelta
        pendingBoopDelta = 0
        if let newServerCount = await petsService.incrementBoopCount(petID: pet.id, by: delta) {
            serverBoopCount = newServerCount
        } else {
            pendingBoopDelta += delta  // retry on next tap / disappear
        }
    }

    // MARK: - Avatar picker handling

    /// Runs the three-step avatar change: load the picked data, show a
    /// local preview, then hand off to `PetsService.updatePetAvatar`.
    /// On success we commit the returned URL to our local `pet` so the
    /// preview state can be cleared cleanly. On failure we surface a
    /// short message and keep whatever the pet had before.
    private func handlePickedAvatar(_ item: PhotosPickerItem) async {
        guard let currentUserID, canEdit else { return }

        avatarErrorMessage = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                avatarErrorMessage = "无法读取照片,请再试一次"
                return
            }

            // Show a preview before the network round-trip so the picker
            // feels responsive. If upload fails, we clear the preview so
            // the UI falls back to the previous avatar_url.
            if let uiImage = UIImage(data: data) {
                pickedAvatarPreview = Image(uiImage: uiImage)
            }

            isUploadingAvatar = true
            defer { isUploadingAvatar = false }

            if let newURL = await petsService.updatePetAvatar(pet, for: currentUserID, data: data) {
                pet.avatar_url = newURL
                pickedAvatarPreview = nil  // real URL is now live
            } else {
                pickedAvatarPreview = nil
                avatarErrorMessage = petsService.errorMessage ?? "上传失败,请再试一次"
            }
        } catch {
            pickedAvatarPreview = nil
            avatarErrorMessage = "无法读取照片: \(error.localizedDescription)"
        }

        pickedAvatarItem = nil
    }

    // MARK: - Posts grid

    private var postsGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PawPalTheme.orange)
                Text("动态")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.primaryText)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            if postsService.isLoadingPetPosts && postsService.petPosts.isEmpty {
                ProgressView().padding(.top, 48)
            } else if postsService.petPosts.isEmpty {
                emptyPostsState
            } else {
                realPostsGrid
            }
        }
    }

    private var emptyPostsState: some View {
        VStack(spacing: 12) {
            Text("🐾")
                .font(.system(size: 44))
                .padding(.top, 40)
            Text("还没有动态")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
            Text("\(pet.name) 还没有发布任何动态")
                .font(.system(size: 14))
                .foregroundStyle(PawPalTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 48)
    }

    private var realPostsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ForEach(postsService.petPosts) { post in
                NavigationLink(value: post) {
                    petPostTile(post)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    /// Unified outer height for every grid tile — both image and
    /// text-only variants use the same value so side-by-side they read
    /// as the same card size, just with different interior content. If
    /// the two tile types had different natural heights, adjacent rows
    /// would look jagged and the image tile would visibly "dominate"
    /// the row with a taller photo than the cream text card.
    private static let tileHeight: CGFloat = 220

    private func petPostTile(_ post: RemotePost) -> some View {
        // Two distinct tile recipes — same outer dimensions, different
        // interior so adjacent text/image tiles don't read as the same
        // visual block:
        //
        //   * Image tile  → inset thumbnail + caption + counts
        //   * Text-only   → one solid cream card, counts inline at the
        //                   bottom of the cream
        //
        // Earlier the image tile had an edge-to-edge 150pt photo that
        // made the image-led tile look shorter than the text tiles
        // beside it (the text tile was minHeight 210 → taller overall).
        // The photo is now an inset thumbnail of height 110 with a
        // caption area that matches the text tile's content area, so
        // both recipes compose to the same outer height.
        Group {
            if let imageURL = post.imageURLs.first {
                imageTile(post, imageURL: imageURL)
            } else {
                textOnlyTile(post)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.tileHeight)
        .background(PawPalTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: PawPalTheme.softShadow, radius: 8, y: 3)
    }

    /// Image-led tile: inset thumbnail (not edge-to-edge) with its own
    /// rounded corners, sitting above a caption + counts footer. The
    /// inset + smaller photo is what brings this tile to the same outer
    /// height as `textOnlyTile` instead of bleeding to a taller silhouette.
    private func imageTile(_ post: RemotePost, imageURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    PawPalTheme.cardSoft.overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(PawPalTheme.tertiaryText)
                    )
                default:
                    PawPalTheme.cardSoft.overlay(ProgressView())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(post.caption)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PawPalTheme.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Label("\(post.likeCount)", systemImage: "heart")
                    Label("\(post.commentCount)", systemImage: "message")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PawPalTheme.tertiaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Text-only tile: a single solid cream card with the caption as the
    /// hero and the like / comment counts sitting on the cream at the
    /// bottom — no white strip. This is what visually separates it from
    /// the image tile (which has a white background with an inset
    /// thumbnail). If both tile types had the same background style,
    /// side-by-side they'd read as the same silhouette.
    private func textOnlyTile(_ post: RemotePost) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PawPalTheme.orange)
                Text(post.caption)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PawPalTheme.primaryText)
                    .lineLimit(6)
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Label("\(post.likeCount)", systemImage: "heart")
                Label("\(post.commentCount)", systemImage: "message")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(PawPalTheme.tertiaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PawPalTheme.cardSoft)
    }

    // MARK: - Helpers

    private func speciesEmoji(for species: String) -> String {
        switch species.lowercased() {
        case "dog": return "🐶"
        case "cat": return "🐱"
        case "rabbit", "bunny": return "🐰"
        case "bird": return "🦜"
        case "hamster": return "🐹"
        case "fish": return "🐟"
        default: return "🐾"
        }
    }

    /// Ensures a numeric-only value (e.g. "3", "25") gets a unit appended.
    /// Values that already contain a CJK character (i.e. the unit is already there,
    /// e.g. "3 岁", "3个月", "25 公斤") are returned unchanged.
    private func withUnit(_ value: String, defaultUnit: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let hasCJK = trimmed.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF }
        return hasCJK ? trimmed : "\(trimmed) \(defaultUnit)"
    }

    private func localizedSex(_ sex: String) -> String {
        switch sex {
        case "Male":   return "公"
        case "Female": return "母"
        default:       return sex
        }
    }

    private func speciesDisplayName(_ species: String) -> String {
        switch species.lowercased() {
        case "dog": return "狗狗"
        case "cat": return "猫咪"
        case "rabbit", "bunny": return "兔兔"
        case "bird": return "鸟类"
        case "hamster": return "仓鼠"
        case "fish": return "鱼类"
        default: return species
        }
    }
}
