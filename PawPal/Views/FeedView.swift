import SwiftUI
import UIKit

struct FeedView: View {
    @Bindable var authManager: AuthManager
    @StateObject private var postsService  = PostsService()
    @StateObject private var followService = FollowService()
    @State private var commentingPost: RemotePost?
    @State private var pendingDeletePost: RemotePost?
    @State private var toastMessage: String?

    private var myID: UUID? { authManager.currentUser?.id }

    // True once we've loaded follows at least once
    private var hasLoadedFollows: Bool { !followService.isLoading }
    // User follows at least one person → show filtered feed
    private var isFiltered: Bool { !followService.followingIDs.isEmpty }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header

                // Subtle nudge banner when user follows nobody yet
                if hasLoadedFollows && !isFiltered {
                    followNudgeBanner
                }

                if postsService.isLoadingFeed && postsService.feedPosts.isEmpty {
                    feedSkeleton
                } else if postsService.feedPosts.isEmpty {
                    emptyFeed
                } else {
                    ForEach(postsService.feedPosts, id: \.id) { post in
                        PostCard(
                            post: post,
                            currentUserID: myID,
                            commentCount: postsService.commentCount(for: post.id),
                            isFollowingOwner: followService.isFollowing(post.owner_user_id),
                            isOwnPost: post.owner_user_id == myID,
                            onLike: {
                                if let uid = myID {
                                    await postsService.toggleLike(postID: post.id, userID: uid)
                                }
                            },
                            onComment: { commentingPost = post },
                            onFollow: { await followService.toggleFollow(targetID: post.owner_user_id) },
                            onDelete: { pendingDeletePost = post }
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(PawPalBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await refreshFeed() }
        .task {
            if let uid = myID {
                await followService.loadFollowing(for: uid)
            }
            await refreshFeed()
        }
        // Re-filter the feed whenever the following list changes
        .onChange(of: followService.followingIDs) { _, _ in
            Task { await refreshFeed() }
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
            PetProfileView(pet: pet)
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
        .sheet(item: $commentingPost) { post in
            CommentsView(
                postID: post.id,
                currentUserID: myID,
                currentUserDisplayName: authManager.currentProfile?.display_name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? authManager.currentProfile!.display_name!
                    : (authManager.currentUser?.displayName ?? authManager.currentUser?.email?.components(separatedBy: "@").first ?? "用户"),
                currentUsername: authManager.currentProfile?.username,
                postsService: postsService
            )
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
        if let uid = myID, isFiltered {
            await postsService.loadFeed(followingIDs: followService.feedFilter(includingSelf: uid))
        } else {
            await postsService.loadFeed()
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
                .background(.white, in: Circle())
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
            ForEach(0..<3, id: \.self) { _ in skeletonCard }
        }
    }

    private var skeletonCard: some View {
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
        .background(PawPalTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .redacted(reason: .placeholder)
    }
}

// MARK: - PostCard

struct PostCard: View {
    let post: RemotePost
    let currentUserID: UUID?
    let commentCount: Int
    let isFollowingOwner: Bool
    let isOwnPost: Bool
    let onLike: () async -> Void
    let onComment: () -> Void
    let onFollow: () async -> Void
    let onDelete: () -> Void

    @State private var likeAnimating = false
    @State private var followAnimating = false

    private var isLiked: Bool {
        guard let uid = currentUserID else { return false }
        return post.isLiked(by: uid)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader
            captionText
            if !post.imageURLs.isEmpty { imageSection }
            if let mood = post.mood, !mood.isEmpty {
                PawPalPill(text: mood, systemImage: "sparkles", tint: PawPalTheme.orangeSoft)
            }
            reactionRow
        }
        .pawPalCard()
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack(spacing: 12) {
            petAvatarCircle

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(post.pet?.name ?? "未知宠物")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(PawPalTheme.primaryText)
                    if let species = post.pet?.species, !species.isEmpty {
                        PawPalPill(text: speciesDisplayName(species), systemImage: nil, tint: PawPalTheme.orange.opacity(0.7))
                    }
                }
                Text(relativeTime(from: post.created_at))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            petAvatarLink
            Spacer()

            if isOwnPost {
                Menu {
                    Button(role: .destructive, action: onDelete) {
                        Label("删除动态", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(PawPalTheme.secondaryText)
                        .frame(width: 32, height: 32)
                        .background(PawPalTheme.cardSoft, in: Circle())
                }
                .buttonStyle(.plain)
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
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [PawPalTheme.orange.opacity(0.25), PawPalTheme.cardSoft],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                Text(speciesEmoji(for: post.pet?.species ?? ""))
                    .font(.system(size: 22))
            }
            .overlay(Circle().stroke(PawPalTheme.orange.opacity(0.4), lineWidth: 2))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(post.pet?.name ?? "未知宠物")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(PawPalTheme.primaryText)
                    if let species = post.pet?.species, !species.isEmpty {
                        PawPalPill(text: speciesDisplayName(species), systemImage: nil, tint: PawPalTheme.orange.opacity(0.7))
                    }
                }
                Text(relativeTime(from: post.created_at))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
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
        Text(post.caption)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(PawPalTheme.primaryText)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Images

    private var imageSection: some View {
        let urls = post.imageURLs
        return LazyVStack(spacing: 0) {
            if urls.count == 1 { singleImage(url: urls[0]) }
            else { imageGrid(urls: urls) }
        }
    }

    private func singleImage(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 240).clipped()
                    .overlay(alignment: .bottom) {
                        LinearGradient(
                            colors: [Color.black.opacity(0.0), Color.black.opacity(0.28)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 100)
                        .allowsHitTesting(false)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            case .failure:
                imagePlaceholder(height: 240, failed: true)
            default:
                imagePlaceholder(height: 240)
            }
        }
    }

    private func gridColumns(for count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: min(count, 3))
    }

    private func imageGrid(urls: [URL]) -> some View {
        let cols = gridColumns(for: urls.count)
        return LazyVGrid(columns: cols, spacing: 6) {
            ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                            .frame(height: 110).frame(maxWidth: .infinity).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    case .failure:
                        imagePlaceholder(height: 110, failed: true)
                    default:
                        imagePlaceholder(height: 110)
                    }
                }
            }
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
        HStack(spacing: 8) {
            // Like button
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
                HStack(spacing: 5) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .foregroundStyle(isLiked ? Color.red : PawPalTheme.secondaryText)
                        .scaleEffect(likeAnimating ? 1.35 : 1.0)
                    if post.likeCount > 0 {
                        Text("\(post.likeCount)")
                            .contentTransition(.numericText())
                    } else {
                        Text("喜欢")
                    }
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(isLiked ? Color.red : PawPalTheme.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    isLiked
                        ? LinearGradient(colors: [Color.red.opacity(0.15), Color.red.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [PawPalTheme.background, PawPalTheme.background], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Capsule()
                )
                .animation(.easeInOut(duration: 0.15), value: isLiked)
            }
            .buttonStyle(.plain)

            // Comment button
            Button(action: onComment) {
                HStack(spacing: 5) {
                    Image(systemName: "message")
                    if commentCount > 0 {
                        Text("\(commentCount)")
                            .contentTransition(.numericText())
                    } else {
                        Text("评论")
                    }
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(PawPalTheme.background, in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                onComment()
            } label: {
                reactionChip(icon: "pawprint.fill", label: "贴贴")
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private var petAvatarCircle: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [PawPalTheme.orange.opacity(0.25), PawPalTheme.cardSoft],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 44, height: 44)

            if let urlStr = post.pet?.avatar_url, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                    } else {
                        Text(speciesEmoji(for: post.pet?.species ?? ""))
                            .font(.system(size: 22))
                    }
                }
            } else {
                Text(speciesEmoji(for: post.pet?.species ?? ""))
                    .font(.system(size: 22))
            }
        }
        .overlay(Circle().stroke(PawPalTheme.orange.opacity(0.4), lineWidth: 2))
    }

    private func reactionChip(icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            if !label.isEmpty { Text(label) }
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(PawPalTheme.secondaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(PawPalTheme.background, in: Capsule())
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
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60      { return "刚刚" }
        if s < 3600    { return "\(s / 60)分钟前" }
        if s < 86400   { return "\(s / 3600)小时前" }
        if s < 604800  { return "\(s / 86400)天前" }
        let f = DateFormatter()
        f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: date)
    }
}
