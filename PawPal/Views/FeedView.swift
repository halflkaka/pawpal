import SwiftUI
import UIKit

struct FeedView: View {
    @Bindable var authManager: AuthManager
    /// Rotated by MainTabView whenever the user publishes a new post so that
    /// FeedView knows to reload even though feedLoaded is already true.
    var postPublishedID: UUID = UUID()
    @StateObject private var postsService  = PostsService()
    @StateObject private var followService = FollowService()
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

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    // Subtle nudge banner when user follows nobody yet.
                    // Guard with feedLoaded so it doesn't flash above the skeleton
                    // before loadFollowing has even started.
                    if feedLoaded && hasLoadedFollows && !isFiltered {
                        followNudgeBanner
                    }

                    if !feedLoaded || authManager.isRestoringSession || (postsService.isLoadingFeed && postsService.feedPosts.isEmpty) {
                        // Show skeleton only for the first load, or when we truly
                        // have no content yet. Once posts are on screen, keep them
                        // visible during refresh so the scroll view height stays stable.
                        feedSkeleton
                    } else if postsService.feedPosts.isEmpty {
                        emptyFeed
                    } else {
                        ForEach(postsService.feedPosts, id: \.id) { post in
                            NavigationLink(value: post) {
                                PostCard(
                                    post: post,
                                    currentUserID: myID,
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
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background(PawPalBackground())
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
                currentUserDisplayName: authManager.currentProfile?.display_name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? authManager.currentProfile!.display_name!
                    : (authManager.currentUser?.displayName ?? authManager.currentUser?.email?.components(separatedBy: "@").first ?? "用户"),
                currentUsername: authManager.currentProfile?.username
            )
        }
        .navigationDestination(for: RemotePost.self) { post in
            PostDetailView(
                post: post,
                currentUserID: myID,
                isOwnPost: post.owner_user_id == myID,
                currentUserDisplayName: authManager.currentProfile?.display_name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? authManager.currentProfile!.display_name!
                    : (authManager.currentUser?.displayName ?? authManager.currentUser?.email?.components(separatedBy: "@").first ?? "用户"),
                currentUsername: authManager.currentProfile?.username,
                postsService: postsService
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
                .foregroundStyle(PawPalTheme.orange)
                .font(.system(size: 14))
            Text("关注其他铲屎官，首页将只显示他们的动态 🐾")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(PawPalTheme.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PawPalTheme.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("🐾 PawPal")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.primaryText)
                Text("看看你最爱的毛孩子日常动态")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.tertiaryText)
            }
            Spacer()
            Button {
                showToast("搜索功能还在完善中")
            } label: {
                headerButton(systemImage: "magnifyingglass")
            }
            .buttonStyle(.plain)

            Button {
                showToast("通知功能即将上线")
            } label: {
                headerButton(systemImage: "bell.fill", badge: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func headerButton(systemImage: String, badge: Bool = false) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(PawPalTheme.primaryText)
                .frame(width: 38, height: 38)
                .background(PawPalTheme.card, in: Circle())
                .shadow(color: PawPalTheme.shadow, radius: 8, y: 4)
            if badge {
                Circle().fill(Color.red).frame(width: 9, height: 9).offset(x: -2, y: 2)
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
            ForEach(0..<3, id: \.self) { _ in SkeletonCard() }
        }
    }
}

// MARK: - Shimmer Skeleton

private struct SkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle().fill(PawPalTheme.cardSoft).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).fill(PawPalTheme.cardSoft).frame(width: 120, height: 14)
                    RoundedRectangle(cornerRadius: 4).fill(PawPalTheme.cardSoft).frame(width: 80, height: 11)
                }
            }
            RoundedRectangle(cornerRadius: 4).fill(PawPalTheme.cardSoft).frame(maxWidth: .infinity).frame(height: 14)
            RoundedRectangle(cornerRadius: 4).fill(PawPalTheme.cardSoft).frame(width: 200, height: 14)
            RoundedRectangle(cornerRadius: 20).fill(PawPalTheme.cardSoft).frame(maxWidth: .infinity).frame(height: 200)
        }
        .padding(16)
        .background(PawPalTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: PawPalTheme.softShadow, radius: 8, y: 3)
    }
}

// MARK: - PostCard

struct PostCard: View {
    let post: RemotePost
    let currentUserID: UUID?
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader
            captionText
            if !post.imageURLs.isEmpty { imageSection }
            reactionRow
            if commentCount > 0 || !commentPreviews.isEmpty {
                commentPreviewSection
            }
        }
        .pawPalCard()
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack(spacing: 12) {
            petAvatarLink
            Spacer()

            if isOwnPost {
                Menu {
                    Button(role: .destructive, action: onDelete) {
                        Label("删除动态", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(PawPalTheme.tertiaryText)
                        .frame(width: 32, height: 32)
                        .background(PawPalTheme.cardSoft, in: Circle())
                }
            }

            // Follow button — only visible on other people's posts
            if !isOwnPost {
                Button {
                    Task {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { followAnimating = true }
                        await onFollow()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { followAnimating = false }
                    }
                } label: {
                    Text(isFollowingOwner ? "已关注" : "+ 关注")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(isFollowingOwner ? PawPalTheme.secondaryText : .white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            isFollowingOwner
                                ? PawPalTheme.cardSoft
                                : PawPalTheme.orange,
                            in: Capsule()
                        )
                        .scaleEffect(followAnimating ? 0.92 : 1.0)
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: isFollowingOwner)
            }
        }
    }

    private var petAvatarLink: some View {
        let avatarAndInfo = HStack(spacing: 12) {
            PawPalAvatar(
                emoji: speciesEmoji(for: post.pet?.species ?? ""),
                imageURL: post.pet?.avatar_url,
                size: 44,
                background: PawPalTheme.cardSoft,
                ringColor: PawPalTheme.orange.opacity(0.4)
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(post.pet?.name ?? "未知宠物")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(PawPalTheme.primaryText)
                    if let species = post.pet?.species, !species.isEmpty {
                        PawPalPill(text: speciesDisplayName(species), systemImage: nil, tint: PawPalTheme.orange.opacity(0.7))
                    }
                }
                HStack(spacing: 6) {
                    Text(relativeTime(from: post.created_at))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PawPalTheme.tertiaryText)
                    if let mood = post.mood, !mood.isEmpty {
                        Text("·")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(PawPalTheme.tertiaryText)
                        Text(mood)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(PawPalTheme.orangeSoft)
                    }
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

    private var captionText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(post.caption)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(PawPalTheme.primaryText)
                .lineSpacing(4)
                .lineLimit(captionExpanded ? nil : 3)

            if !captionExpanded && post.caption.count > 80 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { captionExpanded = true }
                } label: {
                    Text("展开")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(PawPalTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Images

    private var imageSection: some View {
        let urls = post.imageURLs
        return ZStack {
            LazyVStack(spacing: 0) {
                if urls.count == 1 { singleImage(url: urls[0]) }
                else { imageGrid(urls: urls) }
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

            // Heart burst overlay
            if showDoubleTapHeart {
                Image(systemName: "heart.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
                    .scaleEffect(showDoubleTapHeart ? 1.0 : 0.3)
                    .opacity(showDoubleTapHeart ? 1.0 : 0.0)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func singleImage(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 260).clipped()
                    .overlay(alignment: .bottom) {
                        PawPalTheme.gradientImageOverlay
                            .frame(height: 80)
                            .allowsHitTesting(false)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            case .failure:
                imagePlaceholder(height: 260, failed: true)
            default:
                imagePlaceholder(height: 260)
            }
        }
    }

    private func gridColumns(for count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: min(count, 3))
    }

    private func imageGrid(urls: [URL]) -> some View {
        let cols = gridColumns(for: urls.count)
        return ZStack(alignment: .topTrailing) {
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                                .frame(height: 120).frame(maxWidth: .infinity).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        case .failure:
                            imagePlaceholder(height: 120, failed: true)
                        default:
                            imagePlaceholder(height: 120)
                        }
                    }
                }
            }

            // Image count badge
            Text("\(urls.count)张")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.5), in: Capsule())
                .padding(8)
        }
    }

    private func imagePlaceholder(height: CGFloat, failed: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(PawPalTheme.cardSoft).frame(maxWidth: .infinity).frame(height: height)
            .overlay {
                if failed { Image(systemName: "photo").foregroundStyle(PawPalTheme.tertiaryText) }
                else { ProgressView() }
            }
    }

    // MARK: - Reactions

    private var reactionRow: some View {
        HStack(spacing: 14) {
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
                reactionInlineLabel(
                    icon: isLiked ? "heart.fill" : "heart",
                    text: post.likeCount > 0 ? "\(post.likeCount)" : nil,
                    foreground: isLiked ? PawPalTheme.red : PawPalTheme.secondaryText,
                    scaleIcon: likeAnimating
                )
                .contentTransition(.numericText())
            }
            .buttonStyle(.plain)

            NavigationLink(value: post) {
                reactionInlineLabel(
                    icon: "message",
                    text: commentCount > 0 ? "\(commentCount)" : nil,
                    foreground: PawPalTheme.secondaryText,
                    scaleIcon: false
                )
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                // Share sheet would go here
            } label: {
                reactionInlineLabel(
                    icon: "paperplane",
                    text: nil,
                    foreground: PawPalTheme.secondaryText,
                    scaleIcon: false
                )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    private func reactionInlineLabel(
        icon: String,
        text: String?,
        foreground: Color,
        scaleIcon: Bool
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .scaleEffect(scaleIcon ? 1.14 : 1.0)

            if let text, !text.isEmpty {
                Text(text)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(foreground)
        .frame(minHeight: 22)
    }

    // MARK: - Comment Previews (Instagram / WeChat style)

    private var commentPreviewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if commentCount > commentPreviews.count {
                NavigationLink(value: post) {
                    Text("查看全部 \(commentCount) 条评论")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PawPalTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }

            ForEach(commentPreviews) { comment in
                NavigationLink(value: post) {
                    (Text(comment.authorName)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(PawPalTheme.secondaryText)
                    + Text("  \(comment.content)")
                        .font(.system(size: 12))
                        .foregroundStyle(PawPalTheme.primaryText))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            if commentCount == 0 {
                NavigationLink(value: post) {
                    Text("添加评论…")
                        .font(.system(size: 12))
                        .foregroundStyle(PawPalTheme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PawPalTheme.cardSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
