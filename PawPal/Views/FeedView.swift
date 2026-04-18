import SwiftUI
import UIKit

struct FeedView: View {
    @Bindable var authManager: AuthManager
    /// Rotated by MainTabView whenever the user publishes a new post so that
    /// FeedView knows to reload even though feedLoaded is already true.
    var postPublishedID: UUID = UUID()
    @StateObject private var postsService  = PostsService()
    @StateObject private var followService = FollowService()
    @StateObject private var petsService   = PetsService()
    @State private var pendingDeletePost: RemotePost?
    @State private var toastMessage: String?
    /// Prevents redundant full reloads on every tab switch once feed is populated.
    @State private var feedLoaded = false
    /// Guards the onChange handler — suppresses the spurious refresh triggered
    /// by the very first loadFollowing call during initial task setup.
    @State private var initialLoadDone = false
    @State private var isRefreshingFeed = false

    private var myID: UUID? { authManager.currentUser?.id }

    // True once we've loaded follows at least once
    private var hasLoadedFollows: Bool { !followService.isLoading }
    // User follows at least one person → show filtered feed
    private var isFiltered: Bool { !followService.followingIDs.isEmpty }

    /// Pets from people the user follows that have recent activity in the feed.
    /// Derived from loaded feed posts — each unique pet appears once, ordered
    /// by most recent post. Used to populate the "friends' stories" portion
    /// of the top rail.
    private var followedStoryPets: [RemotePet] {
        let myPetIDs = Set(petsService.pets.map(\.id))
        let sorted = postsService.feedPosts.sorted { $0.created_at > $1.created_at }
        var seen = Set<UUID>()
        var result: [RemotePet] = []
        for post in sorted {
            guard let pet = post.pet else { continue }
            if myPetIDs.contains(pet.id) { continue }
            if seen.contains(pet.id) { continue }
            seen.insert(pet.id)
            result.append(pet)
        }
        return result
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
                    // Stories rail — your pets first (as "your story"), then
                    // followed pets that have recent activity in the feed.
                    // Wrapped in a white "card" so it floats on the cream page
                    // rather than sitting inline like Instagram.
                    if feedLoaded && (!petsService.pets.isEmpty || !followedStoryPets.isEmpty) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 6) {
                                Text("🐾")
                                    .font(.system(size: 13))
                                Text("小伙伴动态")
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
        .task {
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
            initialLoadDone = true
        }
        // Kick off the initial load the moment session restoration completes.
        .onChange(of: authManager.isRestoringSession) { _, isRestoring in
            guard !isRestoring, !feedLoaded, let uid = myID else { return }
            Task {
                await followService.loadFollowing(for: uid)
                await petsService.loadPets(for: uid)
                await refreshFeed()
                feedLoaded = true
                initialLoadDone = true
            }
        }
        // Re-filter the feed whenever the following set actually changes
        // (e.g. user followed/unfollowed from ProfileView).
        // Guard with initialLoadDone so the first-load onChange doesn't fire
        // a second concurrent refreshFeed alongside the one in .task.
        .onChange(of: followService.followingIDs) { oldVal, newVal in
            guard initialLoadDone, newVal != oldVal else { return }
            Task { await refreshFeed() }
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
                initialLoadDone = true
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

    // MARK: - Header (serif wordmark + glass square icons)

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("PawPal")
                .font(PawPalFont.serif(size: 26, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(PawPalTheme.primaryText)
                .lineLimit(1)

            Spacer()

            Button {
                showToast("搜索功能还在完善中")
            } label: {
                headerGlyph(systemImage: "magnifyingglass")
            }
            .buttonStyle(.plain)

            Button {
                showToast("通知功能即将上线")
            } label: {
                headerGlyph(systemImage: "heart", badge: true)
            }
            .buttonStyle(.plain)

            Button {
                showToast("私信功能还在完善中")
            } label: {
                headerGlyph(systemImage: "paperplane")
            }
            .buttonStyle(.plain)
        }
    }

    /// Flat header icon — Instagram's nav icons aren't enclosed in cards,
    /// they're just outlined glyphs sitting on the white bar.
    private func headerGlyph(systemImage: String, badge: Bool = false) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(PawPalTheme.primaryText)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
            if badge {
                Circle()
                    .fill(PawPalTheme.accent)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    .offset(x: 4, y: -4)
            }
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
    /// The signed-in user's own pets — rendered first, treated as "your story"
    /// (no gradient ring, "+" badge overlay, "你的故事" label on the first one).
    let myPets: [RemotePet]
    /// Pets belonging to people the user follows that have recent posts —
    /// rendered after `myPets` with the standard gradient story ring.
    let followedPets: [RemotePet]
    /// If non-nil, shows an "add pet" tile at the end of the rail.
    var onAddPet: (() -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                // Your stories — own pets, no gradient ring, "+" overlay badge.
                ForEach(Array(myPets.enumerated()), id: \.element.id) { idx, pet in
                    NavigationLink(value: pet) {
                        PetStoryBubble(
                            pet: pet,
                            index: idx,
                            isOwnStory: true,
                            label: idx == 0 ? "你的故事" : pet.name
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Friends' stories — followed pets with recent posts, gradient ring.
                ForEach(Array(followedPets.enumerated()), id: \.element.id) { idx, pet in
                    NavigationLink(value: pet) {
                        PetStoryBubble(
                            pet: pet,
                            index: idx + myPets.count,
                            isOwnStory: false,
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
    /// If true, this is the signed-in user's pet — rendered with a hairline
    /// ring and a "+" badge in the corner (Instagram "your story" pattern).
    /// Otherwise renders with the conic gradient ring (a friend's story).
    var isOwnStory: Bool = false
    /// The text under the bubble. For own stories the first pet uses
    /// "你的故事"; everything else falls back to the pet's name.
    var label: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if isOwnStory {
                    // "Your story" ring — quiet hairline so the + badge reads.
                    Circle()
                        .stroke(PawPalTheme.hairline, lineWidth: 1)
                        .frame(width: 64, height: 64)
                } else {
                    // Friend's story — conic gradient outer, white inner gap.
                    Circle()
                        .fill(PawPalTheme.storyRingGradient)
                        .frame(width: 64, height: 64)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 58, height: 58)
                }

                // The actual avatar
                PawPalAvatar(
                    emoji: speciesEmoji(for: pet.species ?? ""),
                    imageURL: pet.avatar_url,
                    size: 54,
                    background: avatarBackground(for: index),
                    dogBreed: pet.species
                )

                // Own-story "+" badge (bottom-right).
                if isOwnStory {
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
                } else {
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
    @State private var saved = false

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

    /// Best-effort handle for the inline-bold caption prefix. We don't join
    /// owner profile into RemotePost yet, so for non-self posts we fall back
    /// to the pet name (still gives the same Instagram-style visual rhythm).
    private var captionHandle: String {
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
    // in. Bookmark is a round chip on the right. This replaces the Instagram
    // "four floating glyphs + separate count line" pattern.

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

            // Bookmark — circular chip on the right, separated from the action pills.
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    saved.toggle()
                }
            } label: {
                Image(systemName: saved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(saved ? PawPalTheme.accent : PawPalTheme.primaryText)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(saved ? PawPalTheme.accentTint : PawPalTheme.cardSoft)
                    )
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
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
