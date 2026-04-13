import SwiftUI

struct PostDetailView: View {
    let post: RemotePost
    let currentUserID: UUID?
    let isOwnPost: Bool
    let currentUserDisplayName: String
    let currentUsername: String?
    @ObservedObject var postsService: PostsService

    @State private var isLiked: Bool
    @State private var likeCount: Int
    @State private var likeAnimating = false

    @State private var comments: [RemoteComment] = []
    @State private var isLoadingComments = false
    @State private var newComment = ""
    @State private var isSubmitting = false
    @State private var pendingDeleteComment: RemoteComment?
    @State private var deletingCommentID: UUID?
    @State private var commentError: String?
    @FocusState private var inputFocused: Bool

    init(
        post: RemotePost,
        currentUserID: UUID?,
        isOwnPost: Bool,
        currentUserDisplayName: String = "用户",
        currentUsername: String? = nil,
        postsService: PostsService
    ) {
        self.post = post
        self.currentUserID = currentUserID
        self.isOwnPost = isOwnPost
        self.currentUserDisplayName = currentUserDisplayName
        self.currentUsername = currentUsername
        self.postsService = postsService
        _isLiked = State(initialValue: currentUserID.map { post.isLiked(by: $0) } ?? false)
        _likeCount = State(initialValue: post.likeCount)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    postContent
                    Divider().padding(.top, 8)
                    commentSectionHeader
                    commentList
                        .padding(.bottom, 100)
                }
            }
            .scrollIndicators(.hidden)
            commentInputBar
        }
        .background(PawPalBackground())
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadComments() }
        .navigationDestination(for: RemotePet.self) { pet in
            PetProfileView(
                pet: pet,
                currentUserID: currentUserID,
                currentUserDisplayName: currentUserDisplayName,
                currentUsername: currentUsername
            )
        }
        .alert("删除评论？", isPresented: deleteCommentAlertBinding, presenting: pendingDeleteComment) { comment in
            Button("删除", role: .destructive) {
                Task { await deleteComment(comment) }
            }
            Button("取消", role: .cancel) { pendingDeleteComment = nil }
        } message: { _ in
            Text("删除后将无法恢复。")
        }
    }

    // MARK: - Post content

    private var postContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            postHeader
            if !post.imageURLs.isEmpty { imageSection }
            captionText
            if let mood = post.mood, !mood.isEmpty {
                PawPalPill(text: mood, systemImage: "sparkles", tint: PawPalTheme.orangeSoft)
            }
            reactionRow
        }
        .padding(16)
    }

    // MARK: - Header

    private var postHeader: some View {
        HStack(spacing: 12) {
            petAvatarLink
            Spacer()
            if isOwnPost {
                Text(relativeTime(from: post.created_at))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var petAvatarLink: some View {
        let avatarContent = HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [PawPalTheme.orange.opacity(0.25), PawPalTheme.cardSoft],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 48, height: 48)
                if let urlStr = post.pet?.avatar_url, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                        } else {
                            Text(speciesEmoji(for: post.pet?.species ?? ""))
                                .font(.system(size: 24))
                        }
                    }
                } else {
                    Text(speciesEmoji(for: post.pet?.species ?? ""))
                        .font(.system(size: 24))
                }
            }
            .overlay(Circle().stroke(PawPalTheme.orange.opacity(0.4), lineWidth: 2))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(post.pet?.name ?? "未知宠物")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
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
                NavigationLink(value: pet) { avatarContent }
                    .buttonStyle(.plain)
            } else {
                avatarContent
            }
        }
    }

    // MARK: - Images

    private var imageSection: some View {
        let urls = post.imageURLs
        return Group {
            if urls.count == 1 {
                AsyncImage(url: urls[0]) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    case .failure:
                        imagePlaceholder(height: 280, failed: true)
                    default:
                        imagePlaceholder(height: 280)
                    }
                }
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: min(urls.count, 3)),
                    spacing: 6
                ) {
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

    // MARK: - Caption

    private var captionText: some View {
        Text(post.caption)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(PawPalTheme.primaryText)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Reactions

    private var reactionRow: some View {
        HStack(spacing: 10) {
            Button {
                guard let uid = currentUserID else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { likeAnimating = true }
                isLiked.toggle()
                likeCount += isLiked ? 1 : -1
                Task {
                    await postsService.toggleLike(postID: post.id, userID: uid)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { likeAnimating = false }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .foregroundStyle(isLiked ? Color.red : PawPalTheme.secondaryText)
                        .scaleEffect(likeAnimating ? 1.35 : 1.0)
                    if likeCount > 0 {
                        Text("\(likeCount)")
                            .contentTransition(.numericText())
                    }
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(isLiked ? Color.red : PawPalTheme.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    isLiked
                        ? LinearGradient(colors: [Color.red.opacity(0.15), Color.red.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [PawPalTheme.cardSoft, PawPalTheme.cardSoft], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .disabled(currentUserID == nil)
            .animation(.easeInOut(duration: 0.15), value: isLiked)

            HStack(spacing: 5) {
                Image(systemName: "message")
                if comments.count > 0 {
                    Text("\(comments.count)")
                }
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(PawPalTheme.secondaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(PawPalTheme.cardSoft, in: Capsule())

            Spacer()
        }
    }

    // MARK: - Comment section

    private var commentSectionHeader: some View {
        HStack {
            Text("评论")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
            if !comments.isEmpty {
                Text("·  \(comments.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PawPalTheme.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var commentList: some View {
        Group {
            if isLoadingComments && comments.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
            } else if comments.isEmpty {
                VStack(spacing: 12) {
                    Text("💬").font(.system(size: 40))
                    Text("还没有评论，来发第一条吧！")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(comments) { comment in
                        commentRow(comment)
                        if comment.id != comments.last?.id {
                            Divider().padding(.leading, 64)
                        }
                    }
                }
            }
        }
    }

    private func commentRow(_ comment: RemoteComment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(PawPalTheme.cardSoft).frame(width: 36, height: 36)
                Image(systemName: "person.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(PawPalTheme.orange)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(comment.authorName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(PawPalTheme.primaryText)
                    Text(relativeTime(from: comment.created_at))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Text(comment.content)
                    .font(.system(size: 14))
                    .foregroundStyle(PawPalTheme.primaryText)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if comment.user_id == currentUserID {
                Button {
                    pendingDeleteComment = comment
                } label: {
                    if deletingCommentID == comment.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Input bar

    private var commentInputBar: some View {
        VStack(spacing: 0) {
            if let commentError {
                Text(commentError)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGroupedBackground))
            }
            Divider()
            HStack(spacing: 10) {
                TextField("发表评论…", text: $newComment, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
                Button {
                    Task { await submitComment() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(canSubmit ? PawPalTheme.orange : PawPalTheme.tertiaryText.opacity(0.4))
                        .scaleEffect(isSubmitting ? 0.88 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isSubmitting)
                }
                .disabled(!canSubmit)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .opacity(currentUserID == nil ? 0.5 : 1)
        .disabled(currentUserID == nil)
    }

    private var canSubmit: Bool {
        !newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting && currentUserID != nil
    }

    // MARK: - Actions

    private func loadComments() async {
        isLoadingComments = true
        comments = await postsService.loadComments(for: post.id)
        isLoadingComments = false
    }

    private func submitComment() async {
        let trimmed = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let userID = currentUserID else { return }

        isSubmitting = true
        commentError = nil
        newComment = ""

        if let comment = await postsService.addComment(postID: post.id, userID: userID, content: trimmed) {
            let local = RemoteComment(
                id: comment.id, post_id: comment.post_id, user_id: comment.user_id,
                content: comment.content, created_at: comment.created_at, profiles: nil,
                username: comment.username ?? currentUsername,
                display_name: comment.display_name ?? currentUserDisplayName
            )
            await loadComments()
            if comments.isEmpty {
                withAnimation { comments = [local] }
            } else if let i = comments.firstIndex(where: { $0.id == local.id }) {
                comments[i] = local
            }
        } else {
            commentError = "评论发送失败，请重试。"
        }
        isSubmitting = false
    }

    private func deleteComment(_ comment: RemoteComment) async {
        guard let userID = currentUserID, deletingCommentID == nil else { return }
        deletingCommentID = comment.id
        let deleted = await postsService.deleteComment(comment.id, postID: post.id, userID: userID)
        if deleted {
            commentError = nil
            withAnimation { comments.removeAll { $0.id == comment.id } }
            await postsService.refreshCommentCount(for: post.id)
        } else {
            commentError = postsService.errorMessage ?? "删除评论失败，请重试。"
        }
        pendingDeleteComment = nil
        deletingCommentID = nil
    }

    private var deleteCommentAlertBinding: Binding<Bool> {
        Binding(get: { pendingDeleteComment != nil }, set: { if !$0 { pendingDeleteComment = nil } })
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
