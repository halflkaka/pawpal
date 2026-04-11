import SwiftUI

struct FeedView: View {
    @Bindable var authManager: AuthManager
    @StateObject private var postsService = PostsService()
    @State private var commentingPost: RemotePost?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header

                if postsService.isLoadingFeed && postsService.feedPosts.isEmpty {
                    feedSkeleton
                } else if postsService.feedPosts.isEmpty {
                    emptyFeed
                } else {
                    ForEach(postsService.feedPosts) { post in
                        PostCard(
                            post: post,
                            currentUserID: authManager.currentUser?.id,
                            commentCount: postsService.commentCount(for: post.id),
                            onLike: {
                                if let uid = authManager.currentUser?.id {
                                    await postsService.toggleLike(postID: post.id, userID: uid)
                                }
                            },
                            onComment: { commentingPost = post }
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
        .refreshable { await postsService.loadFeed() }
        .task { await postsService.loadFeed() }
        .sheet(item: $commentingPost) { post in
            CommentsView(
                postID: post.id,
                currentUserID: authManager.currentUser?.id,
                currentUserDisplayName: authManager.currentProfile?.display_name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? authManager.currentProfile!.display_name!
                    : (authManager.currentUser?.displayName ?? authManager.currentUser?.email?.components(separatedBy: "@").first ?? "用户"),
                currentUsername: authManager.currentProfile?.username,
                postsService: postsService
            )
        }
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
            headerButton(systemImage: "magnifyingglass")
            headerButton(systemImage: "bell.fill", badge: false)
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
    let onLike: () async -> Void
    let onComment: () -> Void

    @State private var likeAnimating = false

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
            Spacer()
            Image(systemName: "ellipsis").foregroundStyle(.secondary).font(.system(size: 14))
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
        return Group {
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
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            case .failure:
                imagePlaceholder(height: 240, failed: true)
            default:
                imagePlaceholder(height: 240)
            }
        }
    }

    private func imageGrid(urls: [URL]) -> some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: min(urls.count, 3))
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
                    isLiked ? Color.red.opacity(0.1) : PawPalTheme.background,
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

            // Boop button (stub)
            reactionChip(icon: "pawprint.fill", label: "贴贴")

            Spacer()
            reactionChip(icon: "paperplane", label: "")
        }
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
