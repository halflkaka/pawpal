import SwiftUI
import UIKit

/// Messaging tab — backed by real `conversations` rows from migration 016
/// via `ChatService`. Up until this screen was refactored the list was
/// populated from `ChatSampleData`, so every row reset on cold start
/// and no two users ever saw the same thread. The UI chrome is the same
/// 2026 prototype (sticky glass header, search, online rail, thread
/// rows) but the data flow is now:
///
///   * Owner id → `ChatService.loadThreads` → `[ChatThread]`
///   * Tapping a row pushes `ChatDetailView(thread:)` which loads +
///     renders the real `messages` log.
///
/// Features that were part of the sample data but aren't part of the
/// DM MVP (online presence, typing indicators, stickers, reactions)
/// aren't rendered — see docs/scope.md. The "在线" rail is hidden
/// entirely for now; when realtime presence lands it'll be re-enabled.
struct ChatListView: View {
    @Bindable var authManager: AuthManager
    @State private var searchText = ""
    @ObservedObject private var chatService = ChatService.shared
    /// We look up the signed-in user's id once per appear because the
    /// sign-in flow can swap users mid-session (after sign-out → sign-in
    /// again). Refetching on task keeps the inbox tied to the current
    /// session.
    @State private var refreshToken = UUID()

    private var filteredThreads: [ChatThread] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return chatService.threads }
        return chatService.threads.filter {
            $0.displayHandle.localizedCaseInsensitiveContains(q)
                || $0.displayName.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                threadList
            }
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .top, spacing: 0) { stickyHeader }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: ChatThread.self) { thread in
            ChatDetailView(thread: thread, authManager: authManager)
        }
        .task(id: refreshToken) {
            guard let userID = authManager.currentUser?.id else { return }
            await chatService.loadThreads(for: userID)
        }
        .refreshable {
            guard let userID = authManager.currentUser?.id else { return }
            await chatService.loadThreads(for: userID)
        }
    }

    // MARK: - Sticky header (serif wordmark + new-chat + search)

    private var stickyHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Text("消息")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(PawPalTheme.primaryText)
                    // HTML ChatList title uses `letterSpacing: -0.8`.
                    .tracking(-0.8)

                Spacer()

                Button {
                    // Compose-new is a follow-up — the MVP relies on the
                    // contacts screen to kick off new DMs (that route
                    // already knows which profiles the user follows).
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(PawPalTheme.primaryText)
                        .frame(width: 36, height: 36)
                        .background(PawPalTheme.cardSoft, in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PawPalTheme.tertiaryText)
                TextField("搜索好友", text: $searchText)
                    .font(.system(size: 15))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(PawPalTheme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(PawPalTheme.cardSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PawPalTheme.hairline).frame(height: 0.5)
        }
    }

    // MARK: - Thread list

    private var threadList: some View {
        LazyVStack(spacing: 0) {
            if chatService.isLoading && chatService.threads.isEmpty {
                ProgressView()
                    .padding(.vertical, 60)
            } else if chatService.threads.isEmpty {
                emptyState
            } else if filteredThreads.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(PawPalTheme.tertiaryText)
                    Text("没有找到匹配的对话")
                        .font(.system(size: 13))
                        .foregroundStyle(PawPalTheme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                ForEach(filteredThreads) { thread in
                    NavigationLink(value: thread) {
                        threadRow(thread)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 6)
    }

    /// Shown when the user has no conversations at all. The follow/search
    /// flow is in the 发现 tab, so we point visitors there rather than
    /// leaving the inbox as a dead screen.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(PawPalTheme.tertiaryText)
            Text("还没有对话")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PawPalTheme.primaryText)
            Text("在发现页搜索好友并私信他们开始聊天")
                .font(.system(size: 13))
                .foregroundStyle(PawPalTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 60)
    }

    private func threadRow(_ thread: ChatThread) -> some View {
        HStack(spacing: 12) {
            avatar(for: thread, size: 54)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(thread.displayHandle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PawPalTheme.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(relativeTime(thread.lastMessageAt))
                        .font(.system(size: 11))
                        .foregroundStyle(PawPalTheme.tertiaryText)
                }
                Text(thread.lastMessagePreview ?? "开始聊天")
                    .font(.system(size: 13))
                    .foregroundStyle(PawPalTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// Avatar bubble for a thread row. Uses the partner's `avatar_url`
    /// when set; otherwise falls back to a coloured initial so rows
    /// never render as an empty circle.
    @ViewBuilder
    private func avatar(for thread: ChatThread, size: CGFloat) -> some View {
        if let urlString = thread.partnerProfile?.avatar_url,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    initialAvatar(for: thread, size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            initialAvatar(for: thread, size: size)
        }
    }

    private func initialAvatar(for thread: ChatThread, size: CGFloat) -> some View {
        let initial: String = {
            if let name = thread.partnerProfile?.display_name?.prefix(1) {
                return String(name)
            }
            if let name = thread.partnerProfile?.username?.prefix(1) {
                return String(name)
            }
            return "?"
        }()
        return Text(initial.uppercased())
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(PawPalTheme.accent, in: Circle())
    }

    /// Short, human-readable time ago ("刚刚", "3 分钟前", "昨天", "4月9日")
    /// for the inbox row. Nil falls back to an empty string so new
    /// threads with no message yet don't render "1970-01-01".
    private func relativeTime(_ date: Date?) -> String {
        guard let date else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f.string(from: date)
        }
        if cal.isDateInYesterday(date) { return "昨天" }
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f.string(from: date)
    }
}
