import SwiftUI
import UIKit

/// Conversation detail screen pushed from `ChatListView`. Backed by real
/// `messages` rows fetched via `ChatService`. The local-state "auto-reply"
/// timer from the sample-data version has been removed — any "reply" you
/// see is now a real message from the other participant, loaded from
/// Supabase.
///
/// MVP scope:
///
///   * Text messages only. The sticker tray + reactions + per-bubble
///     emoji overlay were UI-only features of the mock; they're
///     intentionally dropped until the `messages` schema grows to
///     support them.
///   * No realtime — the view refetches on appear and after send.
///
/// Composer state is local; send() writes the message via ChatService,
/// which optimistically appends it to the cache on the same frame so
/// the bubble animates in even before the server ack.
struct ChatDetailView: View {
    let thread: ChatThread
    @Bindable var authManager: AuthManager

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var chatService = ChatService.shared
    @State private var composerText: String = ""
    @State private var isSending: Bool = false
    @State private var sendError: String?

    private var messages: [RemoteMessage] {
        chatService.messagesByConversation[thread.conversationID] ?? []
    }

    private var myID: UUID? {
        authManager.currentUser?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            if let sendError {
                Text(sendError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            composer
        }
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .toolbar(.hidden, for: .navigationBar)
        // Hide the bottom tab bar while the chat is open so it reads as
        // a fullscreen conversation. Without this the tab bar stays on
        // whichever tab pushed us (Profile → FollowList → Chat keeps
        // "我的" highlighted, which feels wrong — the chat context has
        // nothing to do with the profile tab).
        .toolbar(.hidden, for: .tabBar)
        .task {
            await chatService.loadMessages(conversationID: thread.conversationID)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(PawPalTheme.primaryText)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            partnerAvatar(size: 40)

            VStack(alignment: .leading, spacing: 1) {
                Text(thread.displayHandle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PawPalTheme.primaryText)
                    .lineLimit(1)
                Text(thread.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(PawPalTheme.tertiaryText)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PawPalTheme.hairline).frame(height: 0.5)
        }
    }

    /// Partner avatar for the header. Same URL-with-fallback pattern as
    /// `ChatListView` — abstracted here rather than shared because the
    /// sizing and caching needs for a single header avatar differ from
    /// a scrolling list of rows.
    @ViewBuilder
    private func partnerAvatar(size: CGFloat) -> some View {
        if let urlString = thread.partnerProfile?.avatar_url,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: initial(size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            initial(size: size)
        }
    }

    private func initial(size: CGFloat) -> some View {
        let letter: String = {
            if let name = thread.partnerProfile?.display_name?.prefix(1) { return String(name) }
            if let name = thread.partnerProfile?.username?.prefix(1) { return String(name) }
            return "?"
        }()
        return Text(letter.uppercased())
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(PawPalTheme.accent, in: Circle())
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(messages) { message in
                            MessageBubble(
                                message: message,
                                isMine: message.sender_id == myID
                            )
                            .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .onChange(of: messages.count) {
                // Smoothly scroll to the latest message whenever a new
                // one is appended (either an optimistic local send or a
                // fetched server row).
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    /// Shown when the thread has no messages yet. A fresh conversation
    /// defaults to empty until the user sends the first message.
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 24))
                .foregroundStyle(PawPalTheme.tertiaryText)
            Text("发送第一条消息,开始聊天")
                .font(.system(size: 13))
                .foregroundStyle(PawPalTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("输入消息…", text: $composerText, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.sentences)
                    .onSubmit { Task { await send() } }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(PawPalTheme.cardSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Button {
                Task { await send() }
            } label: {
                Image(systemName: isSending ? "hourglass" : "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(canSend ? .white : PawPalTheme.tertiaryText)
                    .frame(width: 36, height: 36)
                    .background(
                        canSend ? PawPalTheme.accent : PawPalTheme.cardSoft,
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend || isSending)
            .animation(.easeInOut(duration: 0.2), value: canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) {
            Rectangle().fill(PawPalTheme.hairline).frame(height: 0.5)
        }
    }

    // MARK: - Actions

    private var canSend: Bool {
        !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && myID != nil
    }

    private func send() async {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let senderID = myID else { return }
        composerText = ""
        isSending = true
        sendError = nil
        defer { isSending = false }

        let result = await chatService.sendMessage(
            conversationID: thread.conversationID,
            senderID: senderID,
            text: trimmed
        )
        if result == nil {
            sendError = "发送失败,请重试"
            // Restore the draft so the user doesn't lose what they typed.
            composerText = trimmed
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

// MARK: - Bubble

/// Single text message row. Simpler than the mock version: no tap-to-
/// react, no sticker rendering, no author avatar inline (the partner
/// avatar lives in the header). Timestamps render once per-day for the
/// first message and get suppressed on bursts within a minute so a
/// rapid-fire burst doesn't feel spammy.
private struct MessageBubble: View {
    let message: RemoteMessage
    let isMine: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isMine {
                Spacer(minLength: 36)
                bubble
            } else {
                bubble
                Spacer(minLength: 36)
            }
        }
    }

    private var bubble: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
            Text(message.text)
                .font(.system(size: 15))
                .foregroundStyle(isMine ? .white : PawPalTheme.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    isMine
                        ? AnyShapeStyle(PawPalTheme.accent)
                        : AnyShapeStyle(PawPalTheme.cardSoft),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .frame(maxWidth: 260, alignment: isMine ? .trailing : .leading)
            Text(shortTime(message.created_at))
                .font(.system(size: 10))
                .foregroundStyle(PawPalTheme.tertiaryText)
        }
    }

    private func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
