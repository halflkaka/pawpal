import SwiftUI

struct CommentsView: View {
    let postID: UUID
    let currentUserID: UUID?
    @ObservedObject var postsService: PostsService

    @Environment(\.dismiss) private var dismiss
    @State private var comments: [RemoteComment] = []
    @State private var isLoading = false
    @State private var newComment = ""
    @State private var isSubmitting = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if isLoading && comments.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, 80)
                } else if comments.isEmpty {
                    VStack(spacing: 14) {
                        Text("💬")
                            .font(.system(size: 48))
                        Text("还没有评论")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(PawPalTheme.primaryText)
                        Text("来发第一条吧！")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 80)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(comments) { comment in
                                    commentRow(comment)
                                        .id(comment.id)
                                    if comment.id != comments.last?.id {
                                        Divider().padding(.leading, 60)
                                    }
                                }
                            }
                            .padding(.bottom, 80)
                        }
                        .scrollIndicators(.hidden)
                        .onChange(of: comments.count) { _, _ in
                            if let last = comments.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                }

                inputBar
            }
            .navigationTitle("评论")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .task {
            isLoading = true
            comments = await postsService.loadComments(for: postID)
            isLoading = false
        }
    }

    // MARK: - Comment row

    private func commentRow(_ comment: RemoteComment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(PawPalTheme.cardSoft)
                    .frame(width: 36, height: 36)
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                TextField("发表评论…", text: $newComment, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...5)
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
                        .foregroundStyle(
                            canSubmit ? PawPalTheme.orange : PawPalTheme.tertiaryText.opacity(0.4)
                        )
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
    }

    // MARK: - Submit

    private var canSubmit: Bool {
        !newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    private func submitComment() async {
        let trimmed = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let userID = currentUserID else { return }

        isSubmitting = true
        newComment = ""

        if let comment = await postsService.addComment(postID: postID, userID: userID, content: trimmed) {
            withAnimation { comments.append(comment) }
        }

        isSubmitting = false
    }

    // MARK: - Helper

    private func relativeTime(from date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60    { return "刚刚" }
        if s < 3600  { return "\(s / 60)分钟前" }
        if s < 86400 { return "\(s / 3600)小时前" }
        return "\(s / 86400)天前"
    }
}
