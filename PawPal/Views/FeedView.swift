import SwiftUI
import UIKit

/// Identifiable payload for `.fullScreenCover(item:)` — keying on a
/// per-opening UUID lets the presentation refresh cleanly each time the
/// user taps a different rail bubble without a stale viewer lingering.
struct StoryViewerState: Identifiable {
    let id = UUID()
    let bundles: [PetStoriesBundle]
    let initialIndex: Int
}

struct FeedView: View {
    @Bindable var authManager: AuthManager
    /// Rotated by MainTabView whenever the user publishes a new post so that
    /// FeedView knows to reload even though feedLoaded is already true.
    var postPublishedID: UUID = UUID()
    @StateObject private var postsService  = PostsService()
    @StateObject private var followService = FollowService()
    @StateObject private var petsService   = PetsService()
    /// Stories cache (active <24h) keyed by pet_id. Singleton-backed so a
    /// posted story lights up the rail ring without re-fetching. Matches
    /// ChatService / VirtualPetStateStore usage — `@ObservedObject` on a
    /// `.shared` singleton avoids StateObject's "initialised once" trap.
    @ObservedObject private var storyService = StoryService.shared
    @State private var pendingDeletePost: RemotePost?
    @State private var toastMessage: String?
    /// Prevents redundant full reloads on every tab switch once feed is populated.
    @State private var feedLoaded = false
    /// Guards the onChange handler — suppresses the spurious refresh triggered
    /// by the very first loadFollowing call during initial task setup.
    @State private var initialLoadDone = false
    @State private var isRefreshingFeed = false

    // Milestones MVP — birthday card + memory-loop card shown above the
    // stories rail. `milestonesService` is stateless so a struct-level
    // `let` is safe; derivation runs inside `.task` against the already-
    // loaded pets / posts snapshot. `composerPrefill` drives the composer
    // sheet below when the user taps a card.
    private let milestonesService = MilestonesService()
    @State private var milestonesToday: [MilestonesService.Milestone] = []
    @State private var memoriesToday: [MilestonesService.MemoryPost] = []
    @State private var composerPrefill: ComposerPrefill?

    // Playdates MVP — pinned card stack and post-playdate prompt.
    // `playdateService` is observed rather than owned so the service's
    // cache + `.playdateDidChange` broadcasts drive the three derived
    // `@State` collections via `recomputePlaydateCards()`.
    @ObservedObject private var playdateService = PlaydateService.shared
    @State private var pendingInviteRows: [RemotePlaydate] = []
    @State private var upcomingAcceptedRows: [RemotePlaydate] = []
    @State private var postPlaydatePrompt: RemotePlaydate?
    /// When set, FeedView pushes `PlaydateDetailView` via an
    /// `.navigationDestination(item:)`. Distinct from the tab-level
    /// `DeepLinkTarget.playdateID` pathway — tapping a card from the
    /// Feed shouldn't go through the DeepLink resolver (that's for
    /// cross-surface push / cold-start routing).
    @State private var navigatingPlaydate: RemotePlaydate?

    /// Toggles the story composer sheet (tapping an own-pet bubble with the
    /// "+" badge). One bool for the whole rail — the composer picks its own
    /// pet from `petsService.pets`, so we don't need to stash a selection.
    @State private var showingStoryComposer = false
    /// When non-nil, the story viewer is presented. Wrapping both inputs in
    /// a single state value means the `.fullScreenCover(item:)` API can key
    /// the presentation on any opening, and we don't have to juggle two
    /// related pieces of state.
    @State private var viewerState: StoryViewerState?

    private var myID: UUID? { authManager.currentUser?.id }

    // True once we've loaded follows at least once
    private var hasLoadedFollows: Bool { !followService.isLoading }
    // User follows at least one person → show filtered feed
    private var isFiltered: Bool { !followService.followingIDs.isEmpty }

    /// Friends' pets with active (<24h) stories. Drives the non-own half of
    /// the rail — a friend's pet only appears if StoryService has an active
    /// story bucket for them, so the rail is now strictly a *stories* rail
    /// rather than a generic recent-activity list.
    ///
    /// Ordered by newest story first so the pet whose last drop is freshest
    /// sits leftmost. The RemotePet for each entry is read from the joined
    /// `pet` relation on the first story, which StoryService.loadActiveStories
    /// populates via PostgREST's `pets(*)` embed.
    private var followedStoryPets: [RemotePet] {
        let myPetIDs = Set(petsService.pets.map(\.id))

        // Flatten buckets → (pet, newest createdAt) tuples, excluding my
        // own pets (those render in the `myPets` lane above with a "+" badge).
        var candidates: [(pet: RemotePet, newest: Date)] = []
        for (petID, stories) in storyService.activeStoriesByPet {
            guard !myPetIDs.contains(petID),
                  let newestStory = stories.max(by: { $0.created_at < $1.created_at }),
                  let pet = newestStory.pet ?? stories.compactMap(\.pet).first
            else { continue }
            candidates.append((pet, newestStory.created_at))
        }
        return candidates
            .sorted { $0.newest > $1.newest }
            .map(\.pet)
    }

    /// Pre-built viewer payload: every pet (own first, then friends) that
    /// currently has at least one active story, each paired with their
    /// story stack. Tapping any rail bubble opens the viewer at the
    /// matching index in this list.
    private var viewerBundles: [PetStoriesBundle] {
        let ownPetsWithStories = petsService.pets
            .sorted { $0.created_at < $1.created_at }
            .filter { storyService.hasActiveStory(for: $0.id) }

        let friendBundles = followedStoryPets.compactMap { pet -> PetStoriesBundle? in
            guard let stories = storyService.activeStoriesByPet[pet.id], !stories.isEmpty else {
                return nil
            }
            return PetStoriesBundle(pet: pet, stories: stories)
        }

        let ownBundles = ownPetsWithStories.compactMap { pet -> PetStoriesBundle? in
            guard let stories = storyService.activeStoriesByPet[pet.id], !stories.isEmpty else {
                return nil
            }
            return PetStoriesBundle(pet: pet, stories: stories)
        }

        return ownBundles + friendBundles
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(
                    Color.white
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(PawPalTheme.hairline)
                                .frame(height: 0.5)
                        }
                )

            ScrollView {
                // PawPal feed: cream page with a floating white stories card
                // up top, then floating post cards stacked below with 18pt
                // gutters. Distinct from Instagram's flat edge-to-edge look.
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Milestone card — birthday-today surface. Sits above the
                    // stories rail as its own floating white card so the
                    // rhythm is: milestone → memory → stories → nudge →
                    // posts. Both cards no-op until their collection is
                    // non-empty, so users without birthdays see the old flow.
                    if feedLoaded && !milestonesToday.isEmpty {
                        MilestoneTodayCard(
                            milestones: milestonesToday,
                            onTap: { milestone in
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                print("[Milestone] birthday tapped \(milestone.id)")
                                composerPrefill = ComposerPrefill(
                                    petID: milestone.pet.id,
                                    caption: milestone.prefillCaption
                                )
                            }
                        )
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if feedLoaded && !memoriesToday.isEmpty {
                        MemoryTodayCard(
                            memories: memoriesToday,
                            onTap: { memory in
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                print("[Milestone] memory tapped \(memory.id)")
                                composerPrefill = ComposerPrefill(
                                    petID: memory.post.pet?.id ?? memory.post.pet_id,
                                    caption: memory.prefillCaption
                                )
                            }
                        )
                        .padding(.horizontal, 14)
                        .padding(.bottom, 4)
                    }

                    // Playdates MVP — pinned pending-invite + upcoming-
                    // accepted cards. Render order: request cards first
                    // (they're actionable), then countdown cards (they're
                    // just nudges). Both sit below Memory and above Stories.
                    if feedLoaded && !pendingInviteRows.isEmpty {
                        ForEach(pendingInviteRows) { invite in
                            PlaydateRequestCard(
                                playdate: invite,
                                proposerPet: petFor(id: invite.proposer_pet_id),
                                inviteePet: petFor(id: invite.invitee_pet_id),
                                onTap: { navigatingPlaydate = invite }
                            )
                            .padding(.horizontal, 14)
                            .padding(.top, 6)
                        }
                    }

                    if feedLoaded && !upcomingAcceptedRows.isEmpty {
                        ForEach(upcomingAcceptedRows) { accepted in
                            PlaydateCountdownCard(
                                playdate: accepted,
                                proposerPet: petFor(id: accepted.proposer_pet_id),
                                inviteePet: petFor(id: accepted.invitee_pet_id),
                                onTap: { navigatingPlaydate = accepted }
                            )
                            .padding(.horizontal, 14)
                            .padding(.top, 6)
                        }
                    }

                    // Stories rail — your pets first (as "your story"), then
                    // followed pets that have recent activity in the feed.
                    // Wrapped in a white "card" so it floats on the cream page
                    // rather than sitting inline like Instagram.
                    if feedLoaded && (!petsService.pets.isEmpty || !followedStoryPets.isEmpty) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 6) {
                                Text("🐾")
                                    .font(.system(size: 13))
                                // Eyebrow above the stories rail — "毛孩子今日份"
                                // leans harder into the pet-first framing than
                                // the older "小伙伴动态" (which read as
                                // generic-social). Keeps the rhythm warm and
                                // specifically about the pets, not the humans.
                                Text("毛孩子今日份")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(PawPalTheme.secondaryText)
                                    .tracking(0.3)
                                Spacer()
                            }
                            .padding(.horizontal, 18)
                            .padding(.top, 14)
                            .padding(.bottom, 2)

                            PetsStrip(
                                currentDisplayName: displayName,
                                myPets: petsService.pets,
                                followedPets: followedStoryPets,
                                hasActiveStory: { storyService.hasActiveStory(for: $0) },
                                onTapOwnPet: { pet in
                                    // Own pet: with a live story → viewer,
                                    // otherwise open the composer so the
                                    // "+" badge tap always produces a story.
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    if storyService.hasActiveStory(for: pet.id) {
                                        openViewer(for: pet.id)
                                    } else {
                                        showingStoryComposer = true
                                    }
                                },
                                onTapFriendPet: { pet in
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    openViewer(for: pet.id)
                                },
                                onAddPet: nil
                            )
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: PawPalTheme.softShadow, radius: 12, y: 2)
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 14)
                    }

                    // Subtle nudge banner when user follows nobody yet.
                    if feedLoaded && hasLoadedFollows && !isFiltered {
                        followNudgeBanner
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }

                    if !feedLoaded || authManager.isRestoringSession || (postsService.isLoadingFeed && postsService.feedPosts.isEmpty) {
                        feedSkeleton
                    } else if postsService.feedPosts.isEmpty {
                        emptyFeed
                            .padding(.horizontal, 20)
                    } else {
                        ForEach(Array(postsService.feedPosts.enumerated()), id: \.element.id) { idx, post in
                            NavigationLink(value: post) {
                                PostCard(
                                    post: post,
                                    index: idx,
                                    currentUserID: myID,
                                    currentUsername: authManager.currentProfile?.username,
                                    commentCount: postsService.commentCount(for: post.id),
                                    commentPreviews: postsService.commentPreviews[post.id] ?? [],
                                    isFollowingOwner: followService.isFollowing(post.owner_user_id),
                                    isOwnPost: post.owner_user_id == myID,
                                    onLike: {
                                        if let uid = myID {
                                            await postsService.toggleLike(postID: post.id, userID: uid)
                                        }
                                    },
                                    onComment: {},
                                    onFollow: { await followService.toggleFollow(targetID: post.owner_user_id) },
                                    onDelete: { pendingDeletePost = post }
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 18)
                        }

                        Text("你已经看完所有动态 🐾")
                            .font(.system(size: 12))
                            .foregroundStyle(PawPalTheme.tertiaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                            .padding(.bottom, 24)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(PawPalTheme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await refreshFeed()
        }
        .task(id: myID) {
            // Don't attempt any network calls while the Supabase session is still
            // being restored — authenticated requests would fail or return empty
            // results under RLS. The onChange below takes over once it's ready.
            guard !authManager.isRestoringSession else { return }
            if let uid = myID {
                await followService.loadFollowing(for: uid)
                await petsService.loadPets(for: uid)
            }
            // Only do a full reload if the feed hasn't been populated yet.
            // On subsequent tab switches the in-memory feedPosts is still fresh.
            if !feedLoaded {
                await refreshFeed()
                feedLoaded = true
            }
            await reloadStories()
            await recomputeMilestones()
            if let uid = myID {
                await playdateService.loadUpcoming(for: uid)
                recomputePlaydateCards()
            }
            initialLoadDone = true
        }
        // Any mutation to a playdate (accept / decline / cancel / new
        // propose landing via realtime in future) broadcasts
        // `.playdateDidChange`. We re-derive the three state collections
        // rather than patching them in place — cheap (≤ a few dozen
        // rows) and avoids subtle drift between cache and UI.
        .onReceive(NotificationCenter.default.publisher(for: .playdateDidChange)) { _ in
            recomputePlaydateCards()
        }
        // Kick off the initial load the moment session restoration completes.
        .onChange(of: authManager.isRestoringSession) { _, isRestoring in
            guard !isRestoring, !feedLoaded, let uid = myID else { return }
            Task {
                await followService.loadFollowing(for: uid)
                await petsService.loadPets(for: uid)
                await refreshFeed()
                feedLoaded = true
                await reloadStories()
                await recomputeMilestones()
                initialLoadDone = true
            }
        }
        // Re-filter the feed + reload stories whenever the following set
        // actually changes (e.g. user followed/unfollowed from ProfileView).
        // Guard with initialLoadDone so the first-load onChange doesn't fire
        // a second concurrent refreshFeed alongside the one in .task.
        .onChange(of: followService.followingIDs) { oldVal, newVal in
            guard initialLoadDone, newVal != oldVal else { return }
            Task {
                await refreshFeed()
                await reloadStories()
            }
        }
        // When a new post is published from CreatePostView, reset and reload so
        // the author's own new post appears without a manual pull-to-refresh.
        .onChange(of: postPublishedID) { _, _ in
            initialLoadDone = false
            Task {
                if let uid = myID {
                    await followService.loadFollowing(for: uid)
                    await petsService.loadPets(for: uid)
                }
                await refreshFeed()
                feedLoaded = true
                await reloadStories()
                await recomputeMilestones()
                initialLoadDone = true
            }
        }
        // Refresh stories + milestone surfaces when the user's own pet set
        // changes (added / removed a pet, edited a birthday).
        // followingIDs is already handled above.
        .onChange(of: petsService.pets) { _, _ in
            Task {
                await reloadStories()
                await recomputeMilestones()
            }
        }
        // Surface errors as a temporary toast
        .onChange(of: postsService.errorMessage) { _, msg in
            guard let msg else { return }
            showToast(msg)
        }
        .onChange(of: followService.errorMessage) { _, msg in
            guard let msg else { return }
            showToast(msg)
        }
        .overlay(alignment: .top) {
            if let toast = toastMessage {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.75), in: Capsule())
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: toastMessage)
        .navigationDestination(for: RemotePet.self) { pet in
            PetProfileView(
                pet: pet,
                currentUserID: myID,
                currentUserDisplayName: displayName,
                currentUsername: authManager.currentProfile?.username,
                authManager: authManager
            )
        }
        .navigationDestination(for: RemotePost.self) { post in
            PostDetailView(
                post: post,
                currentUserID: myID,
                isOwnPost: post.owner_user_id == myID,
                currentUserDisplayName: displayName,
                currentUsername: authManager.currentProfile?.username,
                postsService: postsService,
                authManager: authManager
            )
        }
        .navigationDestination(item: $navigatingPlaydate) { playdate in
            PlaydateDetailView(
                playdate: playdate,
                proposerPet: petFor(id: playdate.proposer_pet_id),
                inviteePet: petFor(id: playdate.invitee_pet_id),
                currentUserID: myID,
                authManager: authManager
            )
        }
        // Story composer — reached by tapping an own-pet bubble with no
        // active story (the "+" badge). Presented with fullScreenCover
        // so the camera picker (Instagram-style) gets the whole viewport
        // instead of being clipped by a sheet handle. The previous
        // sheet-based layout also had a visible title-clipping bug; the
        // rewrite drops the centered title entirely so the issue can't
        // come back.
        .fullScreenCover(isPresented: $showingStoryComposer) {
            StoryComposerView(
                authManager: authManager,
                pets: petsService.pets,
                onPublished: {
                    showingStoryComposer = false
                    Task { await reloadStories() }
                },
                onCancel: { showingStoryComposer = false }
            )
        }
        // Story viewer — fullScreenCover so the media gets the entire
        // viewport without the sheet's pull-down affordance eating a
        // strip. The item binding keys on the state struct's id, so a
        // rapid re-open (different pet) correctly re-inits the viewer.
        .fullScreenCover(item: $viewerState) { state in
            StoryViewerView(
                petsWithStories: state.bundles,
                initialPetIndex: state.initialIndex,
                currentUserID: myID,
                onDismiss: { viewerState = nil }
            )
        }
        // Composer sheet driven by milestone / memory taps. Identifiable
        // prefill keys the sheet so a fresh tap re-instantiates the
        // composer with the new seed rather than reusing a stale one.
        .sheet(item: $composerPrefill) { prefill in
            NavigationStack {
                CreatePostView(
                    authManager: authManager,
                    onPostPublished: { composerPrefill = nil },
                    prefillCaption: prefill.caption,
                    prefillPetID: prefill.petID
                )
            }
        }
        // Post-playdate prompt — shows once per completed playdate per
        // the UserDefaults flag. CTA bridges into the composer via the
        // same `composerPrefill` pathway used for milestones.
        .sheet(item: $postPlaydatePrompt) { playdate in
            PostPlaydatePromptSheet(
                playdate: playdate,
                otherPetName: otherPetName(for: playdate),
                proposerPetID: playdate.proposer_pet_id,
                inviteePetID: playdate.invitee_pet_id,
                onDismiss: { postPlaydatePrompt = nil },
                onStartPost: { prefill in
                    postPlaydatePrompt = nil
                    composerPrefill = prefill
                }
            )
        }
        .alert("删除这条动态？", isPresented: deletePostAlertBinding, presenting: pendingDeletePost) { post in
            Button("删除", role: .destructive) {
                Task {
                    guard let myID else { return }
                    await postsService.deletePost(post.id, userID: myID)
                    if postsService.errorMessage == nil {
                        showToast("已删除动态")
                    }
                }
            }
            Button("取消", role: .cancel) { pendingDeletePost = nil }
        } message: { _ in
            Text("删除后将无法恢复。")
        }
    }

    private var displayName: String {
        let trimmed = authManager.currentProfile?.display_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return authManager.currentUser?.displayName
            ?? authManager.currentUser?.email?.components(separatedBy: "@").first
            ?? "用户"
    }

    // Feed scoped to followed users + self when the user follows anyone;
    // falls back to all posts so new users always see content.
    private func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            toastMessage = nil
            postsService.errorMessage = nil
            followService.errorMessage = nil
        }
    }

    private var deletePostAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletePost != nil },
            set: { if !$0 { pendingDeletePost = nil } }
        )
    }

    private func refreshFeed() async {
        guard !isRefreshingFeed else { return }
        isRefreshingFeed = true
        defer { isRefreshingFeed = false }

        if let uid = myID, isFiltered {
            await postsService.loadFeed(followingIDs: followService.feedFilter(includingSelf: uid), currentUserID: uid)
        } else {
            await postsService.loadFeed(currentUserID: myID)
        }
    }

    /// Ask StoryService for the current active-story set scoped to the
    /// home rail (my pets ∪ followed friends' pets). Called on initial
    /// load, on pull-to-refresh via the feed onChange, and whenever the
    /// follow or pet graph mutates.
    private func reloadStories() async {
        let myPetIDs = petsService.pets.map(\.id)
        // Followed pet IDs — we don't cache these on FollowService yet
        // (follow graph is user→user, not user→pet), so fall back to
        // "all pets not mine that we've seen via story pushes from the
        // backend". Passing my own + any friend pet ids we already know
        // about from posts keeps the query bounded.
        let friendPetIDs = Set(
            postsService.feedPosts.compactMap { $0.pet?.id }
                .filter { !myPetIDs.contains($0) }
        )
        let ids = Array(Set(myPetIDs).union(friendPetIDs))
        await storyService.loadActiveStories(followedPetIDs: ids.isEmpty ? nil : ids)
    }

    /// Look up the viewer index for the pet tapped on the rail and
    /// present the fullScreenCover. Safely no-ops if the pet isn't in
    /// the viewer bundle list (e.g. their only story just expired).
    private func openViewer(for petID: UUID) {
        let bundles = viewerBundles
        guard let idx = bundles.firstIndex(where: { $0.pet.id == petID }) else { return }
        viewerState = StoryViewerState(bundles: bundles, initialIndex: idx)
    }

    /// Look up a pet by id across the caches FeedView observes: the
    /// viewer's own pets (`petsService.pets`) first, then the subset of
    /// feed posts' joined pet rows (`postsService.feedPosts`). Returns
    /// nil when the pet isn't in either surface — the playdate cards
    /// degrade to a "🐾" emoji placeholder in that case.
    private func petFor(id: UUID) -> RemotePet? {
        if let own = petsService.pets.first(where: { $0.id == id }) { return own }
        if let viaPost = postsService.feedPosts
            .compactMap(\.pet)
            .first(where: { $0.id == id })
        { return viaPost }
        return nil
    }

    /// Returns the non-viewer pet's name, for copy like "和 X 的遛弯…".
    /// Falls back to a generic "毛孩子" when the pet isn't resolvable.
    private func otherPetName(for playdate: RemotePlaydate) -> String {
        let myPetIDs = Set(petsService.pets.map(\.id))
        let otherID: UUID = myPetIDs.contains(playdate.proposer_pet_id)
            ? playdate.invitee_pet_id
            : playdate.proposer_pet_id
        return petFor(id: otherID)?.name ?? "毛孩子"
    }

    /// Re-derive the three playdate-driven `@State` collections from the
    /// service's cache. Pure function — safe to call on every broadcast.
    ///
    /// Rules:
    ///   * pendingInviteRows — `status == proposed` AND viewer is invitee
    ///   * upcomingAcceptedRows — `status == accepted` AND scheduled_at
    ///     is within the next 48h (hide older / farther-out)
    ///   * postPlaydatePrompt — one accepted playdate whose scheduled_at
    ///     was within the last 4h AND the UserDefaults flag is unset.
    ///     First match wins — surfacing one prompt at a time is enough.
    private func recomputePlaydateCards() {
        let all = Array(playdateService.playdates.values)
        let now = Date()
        guard let uid = myID else {
            pendingInviteRows = []
            upcomingAcceptedRows = []
            postPlaydatePrompt = nil
            return
        }

        pendingInviteRows = all
            .filter { $0.status == .proposed && $0.invitee_user_id == uid }
            .sorted { $0.scheduled_at < $1.scheduled_at }

        let fortyEightHours: TimeInterval = 48 * 60 * 60
        upcomingAcceptedRows = all
            .filter {
                $0.status == .accepted &&
                $0.scheduled_at > now &&
                $0.scheduled_at.timeIntervalSince(now) <= fortyEightHours
            }
            .sorted { $0.scheduled_at < $1.scheduled_at }

        // Post-playdate prompt — accepted row whose scheduled_at is in
        // the last 4h and whose one-shot flag hasn't been set. We
        // deliberately ignore `completed` status here because the
        // sweeper that flips `accepted → completed` is deferred per
        // spec §9.5.
        let fourHours: TimeInterval = 4 * 60 * 60
        let candidate = all
            .filter {
                $0.status == .accepted &&
                $0.scheduled_at <= now &&
                now.timeIntervalSince($0.scheduled_at) <= fourHours
            }
            .sorted { $0.scheduled_at > $1.scheduled_at }
            .first { candidate in
                let key = "pawpal.playdate.prompt.\(candidate.id.uuidString)"
                return !UserDefaults.standard.bool(forKey: key)
            }
        // Only replace the binding when the candidate actually changes
        // — otherwise we'd churn the sheet presentation every broadcast.
        if postPlaydatePrompt?.id != candidate?.id {
            postPlaydatePrompt = candidate
        }
    }

    /// Rebuilds the birthday-today and memory-loop surfaces off the
    /// currently loaded pet + own-post snapshots. Cheap — birthday logic
    /// is pure, and memories touch a single capped (≤200) Supabase query
    /// scoped to the current user. Called on initial load, on pet graph
    /// changes, and after a post is published.
    private func recomputeMilestones() async {
        milestonesToday = milestonesService.milestonesToday(forPets: petsService.pets)
        if let uid = myID {
            let memoryPosts = await postsService.loadMemoryPosts(forUser: uid)
            memoriesToday = milestonesService.memoriesToday(forUser: uid, from: memoryPosts)
        } else {
            memoriesToday = []
        }
    }

    // MARK: - Follow nudge banner

    private var followNudgeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2.fill")
                .foregroundStyle(PawPalTheme.accent)
                .font(.system(size: 14))
            Text("关注其他铲屎官，首页将只显示他们的动态 🐾")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(PawPalTheme.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PawPalTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Header (serif wordmark only)
    //
    // The tab bar already carries discovery (发现) and chat (聊天), so the
    // Feed header doesn't need redundant glyph shortcuts. Previously this
    // row also held search/notifications/DM stubs that fired a "功能还在
    // 完善中" toast — they've been removed so first-run users don't tap
    // into dead affordances.

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("PawPal")
                .font(PawPalFont.serif(size: 26, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(PawPalTheme.primaryText)
                .lineLimit(1)

            Spacer()
        }
    }

    // MARK: - Empty / Loading states

    private var emptyFeed: some View {
        VStack(spacing: 16) {
            Text("🐾").font(.system(size: 52))
            Text("还没有动态")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
            Text("做第一个发帖的人吧，去下方发布页分享一下。")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var feedSkeleton: some View {
        VStack(spacing: 18) {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonCard()
                    .padding(.horizontal, 14)
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Pets Strip (feed stories rail)

/// Horizontally-scrolling rail of the user's pets. Tapping a pet avatar
/// navigates to its profile — same as the design's stories row, but bound to
/// real data rather than a separate "stories" backend.
struct PetsStrip: View {
    let currentDisplayName: String
    /// The signed-in user's own pets — rendered first. If a pet has an
    /// active story the ring lights up + tap opens the viewer; otherwise
    /// a "+" badge hints that tapping will compose a new story.
    let myPets: [RemotePet]
    /// Friends' pets with active stories. Rendered with the gradient
    /// ring; friends without an active story don't appear here at all
    /// (the rail is stories-only, not a general activity list).
    let followedPets: [RemotePet]
    /// Active-story predicate — used to decide whether to draw the
    /// gradient ring and whether a tap routes to viewer vs. composer.
    var hasActiveStory: (UUID) -> Bool = { _ in false }
    /// Tap handler for the user's own pet bubbles. Receives the tapped pet
    /// and routes to composer (no story) or viewer (has story) upstream.
    var onTapOwnPet: (RemotePet) -> Void = { _ in }
    /// Tap handler for a friend's pet bubble — always opens the viewer.
    var onTapFriendPet: (RemotePet) -> Void = { _ in }
    /// If non-nil, shows an "add pet" tile at the end of the rail.
    var onAddPet: (() -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                // Your stories — own pets. Ring + tap behaviour depend on
                // whether that pet already has an active story.
                ForEach(Array(myPets.enumerated()), id: \.element.id) { idx, pet in
                    Button {
                        onTapOwnPet(pet)
                    } label: {
                        PetStoryBubble(
                            pet: pet,
                            index: idx,
                            isOwnStory: true,
                            hasActiveStory: hasActiveStory(pet.id),
                            label: idx == 0 ? "你的故事" : pet.name
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Friends' stories — only pets with active stories make it
                // here (the caller filters), so every bubble gets the ring.
                ForEach(Array(followedPets.enumerated()), id: \.element.id) { idx, pet in
                    Button {
                        onTapFriendPet(pet)
                    } label: {
                        PetStoryBubble(
                            pet: pet,
                            index: idx + myPets.count,
                            isOwnStory: false,
                            hasActiveStory: true,
                            label: pet.name
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let onAddPet {
                    Button(action: onAddPet) {
                        addPetBubble
                    }
                    .buttonStyle(.plain)
                }
            }
            // Instagram stories rail: tighter padding, smaller gaps.
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
    }

    private var addPetBubble: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(PawPalTheme.hairline, style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    .frame(width: 64, height: 64)
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(PawPalTheme.secondaryText)
            }
            Text("添加")
                .font(.system(size: 12))
                .foregroundStyle(PawPalTheme.secondaryText)
        }
    }
}

private struct PetStoryBubble: View {
    let pet: RemotePet
    let index: Int
    /// If true, this is the signed-in user's pet. Own bubbles with no
    /// active story show a "+" badge (tap → composer); own bubbles with
    /// a story show the gradient ring (tap → viewer). Friend bubbles
    /// always have the ring since the caller filters non-story friends
    /// out of the rail entirely.
    var isOwnStory: Bool = false
    /// Whether this pet currently has an active (<24h) story. Drives the
    /// ring colour for own bubbles — friends default to true because the
    /// rail doesn't include friends without stories.
    var hasActiveStory: Bool = false
    /// The text under the bubble. For own stories the first pet uses
    /// "你的故事"; everything else falls back to the pet's name.
    var label: String? = nil

    /// Show the gradient "live story" ring when the pet has a story.
    /// This is how the Instagram-style "unseen" affordance reads — a
    /// hairline ring means "nothing new", gradient ring means "tap me".
    private var showRing: Bool { hasActiveStory }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if showRing {
                    // Live story — conic gradient outer, white inner gap
                    // so the avatar sits on its own disc (not on coloured
                    // pixels).
                    Circle()
                        .fill(PawPalTheme.storyRingGradient)
                        .frame(width: 64, height: 64)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 58, height: 58)
                } else {
                    // Quiet hairline — reads as "no new story yet".
                    Circle()
                        .stroke(PawPalTheme.hairline, lineWidth: 1)
                        .frame(width: 64, height: 64)
                }

                // The actual avatar
                PawPalAvatar(
                    emoji: speciesEmoji(for: pet.species ?? ""),
                    imageURL: pet.avatar_url,
                    size: 54,
                    background: avatarBackground(for: index),
                    dogBreed: pet.species
                )
                // Key the AsyncImage identity on the stable URL so the
                // loaded photo survives re-rendering of the rail (e.g.
                // when StoryService reloads and flips the ring on).
                .id(pet.avatar_url ?? pet.id.uuidString)

                // Own pet with no story yet → "+" badge so the tap
                // affordance reads as "compose new story".
                if isOwnStory && !hasActiveStory {
                    Circle()
                        .fill(PawPalTheme.accent)
                        .frame(width: 20, height: 20)
                        .overlay {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .overlay {
                            Circle().stroke(Color.white, lineWidth: 2)
                        }
                        .offset(x: 22, y: 22)
                } else if !isOwnStory {
                    // Friend bubble — small species-emoji badge in the
                    // bottom-right so the rail reads as pet-themed, not generic.
                    Circle()
                        .fill(Color.white)
                        .frame(width: 22, height: 22)
                        .overlay {
                            Text(speciesEmoji(for: pet.species ?? ""))
                                .font(.system(size: 13))
                        }
                        .overlay {
                            Circle().stroke(PawPalTheme.hairline, lineWidth: 1)
                        }
                        .offset(x: 22, y: 22)
                }
            }

            Text(label ?? pet.name)
                .font(.system(size: 12))
                .foregroundStyle(PawPalTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 68)
        }
    }

    /// Cycles through a few warm cream-tinted backgrounds so the rail feels
    /// lively without requiring per-pet metadata.
    private func avatarBackground(for index: Int) -> Color {
        let palette: [Color] = [
            Color(red: 1.00, green: 0.902, blue: 0.800),  // #FFE6CC
            Color(red: 1.00, green: 0.878, blue: 0.800),  // #FFE0CC
            Color(red: 0.992, green: 0.863, blue: 0.725), // #FDDCB9
            Color(red: 0.898, green: 0.925, blue: 0.949)  // #E5ECF2
        ]
        return palette[index % palette.count]
    }

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
}

// MARK: - Shimmer Skeleton

private struct SkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header strip
            HStack(spacing: 10) {
                Circle().fill(PawPalTheme.cardSoft).frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4).fill(PawPalTheme.cardSoft).frame(width: 110, height: 11)
                    RoundedRectangle(cornerRadius: 4).fill(PawPalTheme.cardSoft).frame(width: 70, height: 9)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            // Inset rounded square photo (matches the real card's inset photo)
            GeometryReader { geo in
                Rectangle().fill(PawPalTheme.cardSoft)
                    .frame(width: geo.size.width, height: geo.size.width)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 10)

            // Pill action stubs + caption stubs
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule().fill(PawPalTheme.cardSoft)
                            .frame(width: 60, height: 30)
                    }
                    Spacer()
                    Circle().fill(PawPalTheme.cardSoft).frame(width: 32, height: 32)
                }
                .padding(.top, 12)

                RoundedRectangle(cornerRadius: 4).fill(PawPalTheme.cardSoft)
                    .frame(width: 120, height: 11)
                RoundedRectangle(cornerRadius: 4).fill(PawPalTheme.cardSoft)
                    .frame(maxWidth: .infinity).frame(height: 11)
                RoundedRectangle(cornerRadius: 4).fill(PawPalTheme.cardSoft)
                    .frame(width: 180, height: 11)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: PawPalTheme.softShadow, radius: 14, y: 3)
    }
}

// MARK: - PostCard (PawPal floating card on cream page)

struct PostCard: View {
    let post: RemotePost
    /// Index in the feed — used to alternate the subtle polaroid tilt.
    var index: Int = 0
    let currentUserID: UUID?
    /// Only known for own posts; used as the inline-bold handle prefix on the
    /// caption to match HTML's `<b>{user.handle}</b> caption` format.
    var currentUsername: String? = nil
    let commentCount: Int
    /// Last ≤2 comments fetched by PostsService — displayed inline below the card.
    let commentPreviews: [RemoteComment]
    let isFollowingOwner: Bool
    let isOwnPost: Bool
    let onLike: () async -> Void
    let onComment: () -> Void
    let onFollow: () async -> Void
    let onDelete: () -> Void

    @State private var likeAnimating = false
    @State private var followAnimating = false
    @State private var captionExpanded = false
    @State private var showDoubleTapHeart = false

    private var isLiked: Bool {
        guard let uid = currentUserID else { return false }
        return post.isLiked(by: uid)
    }

    // PawPal-style feed: floating white card on cream page. Photo is inset
    // inside the card with rounded corners (distinctly not Instagram's
    // edge-to-edge treatment). Actions live in warm cardSoft pills that
    // combine the icon with the count inline.
    //
    // Layout adapts to the post's content:
    //   • Image post:  header → image → actions → caption → comments
    //   • Text-only:   header → caption (prominent) → actions → comments
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            if !post.imageURLs.isEmpty {
                // Image post — photo comes between header and actions; caption
                // sits below the actions (standard image-post rhythm).
                imageSection
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 10)

                reactionRow
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 2)

                captionText
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
            } else {
                // Text-only post — caption IS the content, so promote it above
                // the actions. Leading edge sits at the card's inner 14pt
                // padding — same x-coordinate as the avatar above it. Body
                // text therefore starts under the profile image, not under
                // the handle. Trailing padding matches on the right.
                textOnlyCaption
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 14)

                reactionRow
                    .padding(.horizontal, 14)
                    .padding(.bottom, 2)
            }

            if commentCount > 0 || !commentPreviews.isEmpty {
                commentPreviewSection
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }
        }
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: PawPalTheme.softShadow, radius: 14, y: 3)
        // Delete affordance for own posts — reached via long-press as a backup.
        .contextMenu {
            if isOwnPost {
                Button(role: .destructive, action: onDelete) {
                    Label("删除动态", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Header (Instagram-style: avatar + bold handle + compact meta)

    private var cardHeader: some View {
        HStack(spacing: 10) {
            petAvatarLink
            Spacer(minLength: 6)

            // Follow pill — small accent-tinted capsule for non-own posts.
            // Flipping to "已关注" swaps to a quiet hairline-bordered capsule.
            if !isOwnPost {
                Button {
                    Task {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { followAnimating = true }
                        await onFollow()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { followAnimating = false }
                    }
                } label: {
                    Text(isFollowingOwner ? "已关注" : "关注")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isFollowingOwner ? PawPalTheme.secondaryText : PawPalTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            if isFollowingOwner {
                                Capsule(style: .continuous)
                                    .stroke(PawPalTheme.hairline, lineWidth: 1)
                            } else {
                                Capsule(style: .continuous)
                                    .fill(PawPalTheme.accentTint)
                            }
                        }
                        .scaleEffect(followAnimating ? 0.92 : 1.0)
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: isFollowingOwner)
            }

            // Own-post: ellipsis opens a Menu (Instagram pattern) — destructive
            // delete is one item, not a single-tap nuke.
            if isOwnPost {
                Menu {
                    Button(role: .destructive) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onDelete()
                    } label: {
                        Label("删除动态", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PawPalTheme.primaryText)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
        }
    }

    private var petAvatarLink: some View {
        let avatarAndInfo = HStack(spacing: 10) {
            // Instagram avatar ~32pt. Still keep the subtle cream background
            // so our brand warmth comes through.
            PawPalAvatar(
                emoji: speciesEmoji(for: post.pet?.species ?? ""),
                imageURL: post.pet?.avatar_url,
                size: 32,
                background: PawPalTheme.cardSoft,
                dogBreed: post.pet?.species
            )
            // Key the AsyncImage identity on the stable avatar URL so the
            // loaded image is preserved across navigation pushes/pops
            // (tapping into a post detail and coming back no longer
            // flashes the illustrated placeholder).
            .id(post.pet?.avatar_url ?? post.id.uuidString)

            VStack(alignment: .leading, spacing: 1) {
                // Handle line — Instagram uses SF Pro Text semibold 14pt.
                HStack(spacing: 4) {
                    Text(post.pet?.name ?? "未知宠物")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PawPalTheme.primaryText)
                        .lineLimit(1)

                    Text("·")
                        .font(.system(size: 12))
                        .foregroundStyle(PawPalTheme.tertiaryText)
                    Text(relativeTime(from: post.created_at))
                        .font(.system(size: 12))
                        .foregroundStyle(PawPalTheme.tertiaryText)
                        .lineLimit(1)
                }

                // Second line — mood tag (Instagram shows location here).
                if let mood = post.mood, !mood.isEmpty {
                    Text(mood)
                        .font(.system(size: 12))
                        .foregroundStyle(PawPalTheme.primaryText)
                        .lineLimit(1)
                } else if let species = post.pet?.species, !species.isEmpty {
                    Text(speciesDisplayName(species))
                        .font(.system(size: 12))
                        .foregroundStyle(PawPalTheme.secondaryText)
                        .lineLimit(1)
                }
            }
        }

        return Group {
            if let pet = post.pet {
                NavigationLink(value: pet) {
                    avatarAndInfo
                }
                .buttonStyle(.plain)
            } else {
                avatarAndInfo
            }
        }
    }

    // MARK: - Caption

    /// Handle for the inline-bold caption prefix. Prefers the real owner
    /// username now that PostsService joins `profiles!owner_user_id(*)`
    /// into every non-minimal selectLevel. Falls back to the cached
    /// currentUsername for own posts when the join is missing, then to
    /// the pet name as a last resort.
    private var captionHandle: String {
        if let handle = post.owner?.username?.trimmingCharacters(in: .whitespacesAndNewlines),
           !handle.isEmpty {
            return handle
        }
        if isOwnPost, let me = currentUsername?.trimmingCharacters(in: .whitespacesAndNewlines), !me.isEmpty {
            return me
        }
        if let name = post.pet?.name, !name.isEmpty { return name }
        return "pawpal"
    }

    private var captionText: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Inline bold handle + caption in a single Text concatenation.
            (
                Text(captionHandle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PawPalTheme.primaryText)
                + Text(" \(post.caption)")
                    .font(.system(size: 14))
                    .foregroundStyle(PawPalTheme.primaryText)
            )
            .lineSpacing(3)
            .lineLimit(captionExpanded ? nil : 2)

            if !captionExpanded && post.caption.count > 70 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { captionExpanded = true }
                } label: {
                    Text("更多")
                        .font(.system(size: 14))
                        .foregroundStyle(PawPalTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Caption variant used when the post has no image. The text IS the
    /// content, so it's promoted above the action row — kept at a normal
    /// reading size in default SF Pro regular. No rounded or serif design:
    /// those read playful-cartoony or editorial-pretentious; plain SF Pro
    /// at 15pt regular is the clean, calm default (previously medium —
    /// user feedback: 字体不要加粗).
    private var textOnlyCaption: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(post.caption)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(PawPalTheme.primaryText)
                .lineSpacing(4)
                .lineLimit(captionExpanded ? nil : 8)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !captionExpanded && post.caption.count > 240 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { captionExpanded = true }
                } label: {
                    Text("展开")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PawPalTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Images (edge-to-edge, 1:1 square — Instagram-style)

    private var imageSection: some View {
        let urls = post.imageURLs
        return GeometryReader { geo in
            let side = geo.size.width
            ZStack {
                Group {
                    if urls.count == 1 { singleImage(url: urls[0], side: side) }
                    else { ImageCarousel(urls: urls, side: side) }
                }
                .onTapGesture(count: 2) {
                    guard !isLiked else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await onLike() }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                        showDoubleTapHeart = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            showDoubleTapHeart = false
                        }
                    }
                }

                // Heart burst overlay — big white heart over the photo.
                if showDoubleTapHeart {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 100))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 2)
                        .scaleEffect(showDoubleTapHeart ? 1.0 : 0.3)
                        .opacity(showDoubleTapHeart ? 1.0 : 0.0)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func singleImage(url: URL, side: CGFloat) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFill()
                    .frame(width: side, height: side)
                    .clipped()
            case .failure:
                imagePlaceholder(side: side, failed: true)
            default:
                imagePlaceholder(side: side)
            }
        }
        // Same fix as the pet avatar — stable URL keys the AsyncImage
        // identity so nav pops don't trigger a re-fetch.
        .id(url.absoluteString)
    }

    private func imagePlaceholder(side: CGFloat, failed: Bool = false) -> some View {
        Rectangle()
            .fill(PawPalTheme.cardSoft)
            .frame(width: side, height: side)
            .overlay {
                if failed { Image(systemName: "photo").foregroundStyle(PawPalTheme.tertiaryText) }
                else { ProgressView() }
            }
    }

    // MARK: - Reactions (PawPal pill-style with inline counts)
    //
    // Like / comment / share sit inside warm cream pills with the count baked
    // in. This replaces the Instagram "four floating glyphs + separate count
    // line" pattern. A bookmark chip lived here previously, but it was a
    // local-only @State toggle with no persistence / no 我的收藏 screen, so
    // it was removed until Phase 6 ships real saves.

    private var reactionRow: some View {
        HStack(spacing: 8) {
            // Like pill — heart + count inline. Fills accent-tinted when liked.
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        likeAnimating = true
                    }
                    await onLike()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        likeAnimating = false
                    }
                }
            } label: {
                // Hide the count text when 0 — an empty pill with just
                // the heart reads cleaner than "♥ 0" and removes the
                // "no engagement" shame. Pills still have matching
                // padding so the row height doesn't shift when a post
                // gains its first like.
                HStack(spacing: post.likeCount > 0 ? 6 : 0) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isLiked ? PawPalTheme.accent : PawPalTheme.primaryText)
                        .scaleEffect(likeAnimating ? 1.25 : 1.0)
                        .contentTransition(.symbolEffect(.replace))
                    if post.likeCount > 0 {
                        Text(shortCount(post.likeCount))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isLiked ? PawPalTheme.accent : PawPalTheme.primaryText)
                            .contentTransition(.numericText())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(isLiked ? PawPalTheme.accentTint : PawPalTheme.cardSoft)
                )
            }
            .buttonStyle(.plain)

            // Comment pill — bubble + count inline.
            NavigationLink(value: post) {
                HStack(spacing: commentCount > 0 ? 6 : 0) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PawPalTheme.primaryText)
                    if commentCount > 0 {
                        Text(shortCount(commentCount))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(PawPalTheme.primaryText)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous).fill(PawPalTheme.cardSoft)
                )
            }
            .buttonStyle(.plain)

            // Share pill — paperplane only, no count.
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "paperplane")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PawPalTheme.primaryText)
                    .offset(x: -0.5, y: -0.5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous).fill(PawPalTheme.cardSoft)
                    )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
    }

    /// Shortens large numbers to `1.2万` / `1.2M` style for inline counts.
    private func shortCount(_ n: Int) -> String {
        if n <= 0 { return "0" }
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
                .replacingOccurrences(of: ".0M", with: "M")
        }
        if n >= 10_000 {
            return String(format: "%.1f万", Double(n) / 10_000)
                .replacingOccurrences(of: ".0万", with: "万")
        }
        return "\(n)"
    }

    // MARK: - Comment Previews (muted "View all" link + inline rows)

    private var commentPreviewSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if commentCount > 0 {
                NavigationLink(value: post) {
                    Text("查看全部 \(commentCount) 条评论")
                        .font(.system(size: 13))
                        .foregroundStyle(PawPalTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }

            ForEach(commentPreviews.prefix(2)) { comment in
                NavigationLink(value: post) {
                    (Text(comment.authorName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PawPalTheme.primaryText)
                    + Text(" \(comment.content)")
                        .font(.system(size: 13))
                        .foregroundStyle(PawPalTheme.primaryText))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
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

    private func speciesDisplayName(_ english: String) -> String {
        switch english.lowercased() {
        case "dog": return "狗狗"
        case "cat": return "猫咪"
        case "rabbit", "bunny": return "兔兔"
        case "bird": return "鸟类"
        case "hamster": return "仓鼠"
        case "fish": return "鱼类"
        default: return english
        }
    }

    private func relativeTime(from date: Date) -> String {
        let s = max(0, Int(-date.timeIntervalSinceNow))
        if s < 60      { return "刚刚" }
        if s < 3600    { return "\(s / 60)分钟前" }
        if s < 86400   { return "\(s / 3600)小时前" }
        if s < 604800  { return "\(s / 86400)天前" }
        let f = DateFormatter()
        f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: date)
    }
}

// MARK: - ImageCarousel (swipeable multi-photo viewport, edge-to-edge square)

/// Instagram-style edge-to-edge square photo carousel. Fills the full feed
/// width, 1:1 aspect. `idx/count` badge top-right; dot indicators overlaid
/// on the photo bottom (Instagram uses white dots; here we brighten them for
/// legibility on varied photo colors).
private struct ImageCarousel: View {
    let urls: [URL]
    /// Width of the feed / full edge-to-edge square side.
    let side: CGFloat
    @State private var currentIndex: Int = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $currentIndex) {
                ForEach(Array(urls.enumerated()), id: \.offset) { idx, url in
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                                .frame(width: side, height: side)
                                .clipped()
                        case .failure:
                            carouselPlaceholder(failed: true)
                        default:
                            carouselPlaceholder(failed: false)
                        }
                    }
                    // Key the AsyncImage on the URL so swiping between
                    // carousel slides — and nav pops back into the feed —
                    // don't re-fetch an already-loaded photo.
                    .id(url.absoluteString)
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(width: side, height: side)

            // Index badge: 1/3 pill, dark blur background.
            Text("\(currentIndex + 1)/\(urls.count)")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.2)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color.black.opacity(0.55))
                )
                .padding(10)
        }
        .overlay(alignment: .bottom) {
            // Dot indicators — white Instagram dots floating near bottom.
            HStack(spacing: 4) {
                ForEach(0..<urls.count, id: \.self) { i in
                    Circle()
                        .fill(i == currentIndex ? Color.white : Color.white.opacity(0.55))
                        .frame(width: 6, height: 6)
                        .animation(.easeInOut(duration: 0.2), value: currentIndex)
                }
            }
            .padding(.bottom, 10)
            .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
        }
    }

    private func carouselPlaceholder(failed: Bool) -> some View {
        Rectangle()
            .fill(PawPalTheme.cardSoft)
            .frame(width: side, height: side)
            .overlay {
                if failed {
                    Image(systemName: "photo").foregroundStyle(PawPalTheme.tertiaryText)
                } else {
                    ProgressView()
                }
            }
    }
}

// MARK: - Composer prefill payload

/// Identifiable payload used by the `sheet(item:)` presentation for the
/// milestone / memory composer. Every tap mints a new id so the sheet
/// re-instantiates cleanly — without that, a second tap after dismiss
/// could reuse a stale composer instance mid-animation.
struct ComposerPrefill: Identifiable, Hashable {
    let id = UUID()
    let petID: UUID
    let caption: String
    /// Optional multi-pet attachment — used by the playdate post-prompt
    /// so both the proposer and invitee pets can be tagged on the same
    /// post. Callers pass either `petID` (single-pet case) OR
    /// `pets` + `petID` (multi-pet — `petID` is the single-pet fallback
    /// the existing composer consumes; honouring `pets` end-to-end is a
    /// follow-up once the composer gains a multi-pet picker).
    let pets: [UUID]?

    init(petID: UUID, caption: String, pets: [UUID]? = nil) {
        self.petID = petID
        self.caption = caption
        self.pets = pets
    }
}

// MARK: - MilestoneTodayCard (today's birthdays — floating white card)

/// Warm-accent card rendered above the stories rail whenever one or
/// more of the user's pets has a birthday today. Tapping the CTA opens
/// the composer pre-seeded with the pet + a celebratory caption. When
/// multiple pets share a birthday, the card becomes a swipeable page
/// view with a `1/N` counter baked into the eyebrow row.
struct MilestoneTodayCard: View {
    let milestones: [MilestonesService.Milestone]
    let onTap: (MilestonesService.Milestone) -> Void

    @State private var currentIndex: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow

            if milestones.count == 1, let only = milestones.first {
                milestoneContent(only)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(milestones.enumerated()), id: \.element.id) { idx, milestone in
                        milestoneContent(milestone)
                            .padding(.horizontal, 18)
                            .padding(.bottom, 16)
                            .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // Height is content-driven by the inner layout's natural
                // size; we only need to give the TabView something to fill.
                .frame(minHeight: 120)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PawPalTheme.accentGlow.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: PawPalTheme.softShadow, radius: 12, y: 2)
    }

    private var eyebrowRow: some View {
        HStack(spacing: 6) {
            Text("🎂")
                .font(.system(size: 13))
            Text("今日纪念日")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PawPalTheme.accent)
                .tracking(0.3)
            Spacer()
            if milestones.count > 1 {
                Text("\(currentIndex + 1)/\(milestones.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(PawPalTheme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(PawPalTheme.cardSoft, in: Capsule())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func milestoneContent(_ milestone: MilestonesService.Milestone) -> some View {
        Button {
            onTap(milestone)
        } label: {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(PawPalTheme.accentTint)
                        .frame(width: 52, height: 52)
                    Text("🎂")
                        .font(.system(size: 26))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(milestone.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(PawPalTheme.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("点一下记录今天 ✨")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PawPalTheme.accent)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PawPalTheme.accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: milestone.id)
    }
}

// MARK: - MemoryTodayCard (N年前的今天 — floating white card)

/// Softer companion to `MilestoneTodayCard`. Surfaces the user's own
/// posts from prior years that share today's month-day, pre-seeding a
/// nostalgic caption when tapped. Image thumbnail is the historic
/// post's first image (if any). Swipeable when multiple memories land
/// on the same day.
struct MemoryTodayCard: View {
    let memories: [MilestonesService.MemoryPost]
    let onTap: (MilestonesService.MemoryPost) -> Void

    @State private var currentIndex: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow

            if memories.count == 1, let only = memories.first {
                memoryContent(only)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(memories.enumerated()), id: \.element.id) { idx, memory in
                        memoryContent(memory)
                            .padding(.horizontal, 18)
                            .padding(.bottom, 16)
                            .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(minHeight: 130)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PawPalTheme.hairline, lineWidth: 0.5)
        )
        .shadow(color: PawPalTheme.softShadow, radius: 12, y: 2)
    }

    private var currentEyebrow: String {
        if memories.indices.contains(currentIndex) {
            return memories[currentIndex].eyebrow
        }
        return memories.first?.eyebrow ?? ""
    }

    private var eyebrowRow: some View {
        HStack(spacing: 6) {
            Text("📷")
                .font(.system(size: 13))
            Text(currentEyebrow)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PawPalTheme.secondaryText)
                .tracking(0.3)
            Spacer()
            if memories.count > 1 {
                Text("\(currentIndex + 1)/\(memories.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(PawPalTheme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(PawPalTheme.cardSoft, in: Capsule())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func memoryContent(_ memory: MilestonesService.MemoryPost) -> some View {
        Button {
            onTap(memory)
        } label: {
            HStack(alignment: .center, spacing: 14) {
                memoryThumb(for: memory)

                VStack(alignment: .leading, spacing: 4) {
                    Text(memory.post.caption)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PawPalTheme.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("点一下记录今天 ✨")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PawPalTheme.accent)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PawPalTheme.accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: memory.id)
    }

    /// Historic post's first image. Falls back to a cream tile with a
    /// camera glyph when the post had no image (text-only memories).
    @ViewBuilder
    private func memoryThumb(for memory: MilestonesService.MemoryPost) -> some View {
        if let url = memory.post.imageURLs.first {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    fallbackThumb
                default:
                    PawPalTheme.cardSoft.overlay(ProgressView())
                }
            }
            .frame(width: 60, height: 60)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            fallbackThumb
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var fallbackThumb: some View {
        PawPalTheme.cardSoft.overlay(
            Image(systemName: "photo")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(PawPalTheme.tertiaryText)
        )
    }
}
