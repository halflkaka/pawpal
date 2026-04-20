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

    /// Presents the compose-new sheet when the `+` button is tapped.
    @State private var isComposePresented = false
    /// Thread pushed after the compose sheet (or any future entry point)
    /// resolves a conversation id. Using `navigationDestination(item:)`
    /// — same pattern as FollowListView — avoids manual NavigationPath
    /// juggling.
    @State private var pendingThread: ChatThread?
    /// Pet-first pass (P0 #3): each thread row renders the partner's
    /// first pet as a small badge in the bottom-right of their avatar,
    /// so the inbox reads as "my pet's friends' pets" rather than a
    /// human-to-human list. Keyed by the partner's user id; falls back
    /// to no badge for partners who have no pets yet.
    @State private var featuredPets: [UUID: RemotePet] = [:]
    /// Shared PetsService so the featured-pet fan-out benefits from
    /// any other surface's cached writes (avatar updates, new pets).
    @ObservedObject private var petsService = PetsService.shared

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
        // When the compose sheet picks a partner, we push into the real
        // ChatDetailView via this item-bound destination. Same pattern as
        // FollowListView — keeps the sheet from having to manage its own
        // navigation.
        .navigationDestination(item: $pendingThread) { thread in
            ChatDetailView(thread: thread, authManager: authManager)
        }
        .sheet(isPresented: $isComposePresented) {
            if let userID = authManager.currentUser?.id {
                ComposeNewChatSheet(
                    viewerID: userID,
                    onStartConversation: { profile in
                        await startConversation(with: profile)
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .task(id: refreshToken) {
            guard let userID = authManager.currentUser?.id else { return }
            await chatService.loadThreads(for: userID)
            await loadFeaturedPetsForThreads()
        }
        .refreshable {
            guard let userID = authManager.currentUser?.id else { return }
            await chatService.loadThreads(for: userID)
            await loadFeaturedPetsForThreads()
        }
    }

    /// Fan-out fetch of every partner's first pet so the thread rows
    /// can badge the user avatar with a pet avatar. One batched query
    /// across all visible threads — see `PetsService.loadFeaturedPets`
    /// for the query shape. Called after threads resolve on load and
    /// pull-to-refresh.
    private func loadFeaturedPetsForThreads() async {
        let partnerIDs = Array(Set(chatService.threads.map(\.partnerID)))
        guard !partnerIDs.isEmpty else {
            featuredPets = [:]
            return
        }
        featuredPets = await petsService.loadFeaturedPets(for: partnerIDs)
    }

    /// Starts (or re-opens) a DM with the given profile and routes the
    /// user into ChatDetailView. Called from the compose-new sheet row
    /// after it dismisses itself. Mirrors FollowListView.openChat so the
    /// two surfaces share the same flow.
    private func startConversation(with partner: RemoteProfile) async {
        guard let viewerID = authManager.currentUser?.id else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard let conversationID = await ChatService.shared.startConversation(
            userA: viewerID,
            userB: partner.id
        ) else { return }
        pendingThread = ChatThread(
            conversationID: conversationID,
            partnerID: partner.id,
            partnerProfile: partner,
            lastMessagePreview: nil,
            lastMessageAt: nil,
            createdAt: Date()
        )
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
                    // Compose-new sheet — reuses FollowService to list
                    // people the user follows and opens a DM via
                    // ChatService.startConversation (same flow as
                    // FollowListView). Lets a user with zero threads reach
                    // a real conversation from inside the 聊天 tab, without
                    // round-tripping through 发现 first.
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    isComposePresented = true
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
                .overlay(alignment: .bottomTrailing) {
                    if let pet = featuredPets[thread.partnerID] {
                        petBadge(for: pet)
                            .offset(x: 3, y: 3)
                    }
                }

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

    /// Small featured-pet badge pinned to the bottom-right of the partner
    /// avatar. Keeps the inbox pet-first — the user's face is the label,
    /// their pet is the accent. White ring keeps it legible on every
    /// avatar variant.
    @ViewBuilder
    private func petBadge(for pet: RemotePet) -> some View {
        let badge: CGFloat = 22
        ZStack {
            if let urlStr = pet.avatar_url, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        petBadgeFallback(for: pet)
                    }
                }
                .frame(width: badge, height: badge)
                .clipShape(Circle())
            } else {
                petBadgeFallback(for: pet)
                    .frame(width: badge, height: badge)
            }
        }
        .overlay(Circle().stroke(Color.white, lineWidth: 2))
    }

    @ViewBuilder
    private func petBadgeFallback(for pet: RemotePet) -> some View {
        ZStack {
            Circle().fill(PawPalTheme.cardSoft)
            Text(speciesEmoji(for: pet.species ?? ""))
                .font(.system(size: 12))
        }
    }

    private func speciesEmoji(for species: String) -> String {
        switch species.lowercased() {
        case "dog":             return "🐶"
        case "cat":             return "🐱"
        case "rabbit", "bunny": return "🐰"
        case "bird":            return "🦜"
        case "fish":            return "🐟"
        case "hamster":         return "🐹"
        default:                return "🐾"
        }
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

// MARK: - Compose New Chat Sheet
//
// Lists the people the viewer follows so they can kick off a DM without
// leaving the 聊天 tab. Matches FollowListView's row shape (avatar + handle
// + display name) so the two surfaces feel like siblings rather than one-off
// designs. Loads lazily in a `.task` — the sheet renders its skeleton
// immediately and fills in once `loadFollowingProfiles` resolves.
private struct ComposeNewChatSheet: View {
    let viewerID: UUID
    /// Called when the viewer taps a row. The parent dismisses the sheet
    /// and pushes ChatDetailView for the resolved conversation.
    let onStartConversation: (RemoteProfile) async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var followService = FollowService()
    @ObservedObject private var petsService = PetsService.shared
    @State private var profiles: [RemoteProfile] = []
    /// Pet-first pass (P0 #3): mirror the inbox list row treatment — a
    /// small pet badge in the bottom-right of each user avatar. Keyed
    /// by user id; absent for users with no pets yet.
    @State private var featuredPets: [UUID: RemotePet] = [:]
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if profiles.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("发起聊天")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(PawPalTheme.primaryText)
                }
            }
        }
        .task {
            profiles = await followService.loadFollowingProfiles(for: viewerID)
            isLoading = false
            // Fan-out the featured-pet query once we know who the viewer
            // follows — same shape as the FollowListView / ChatListView
            // loaders so the compose sheet doesn't read as a regressed
            // human-first surface.
            let ids = profiles.map(\.id)
            if !ids.isEmpty {
                featuredPets = await petsService.loadFeaturedPets(for: ids)
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(profiles, id: \.id) { profile in
                    Button {
                        dismiss()
                        Task { await onStartConversation(profile) }
                    } label: {
                        row(for: profile)
                    }
                    .buttonStyle(.plain)
                    Divider()
                        .padding(.leading, 76)
                }
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }

    private func row(for profile: RemoteProfile) -> some View {
        HStack(spacing: 12) {
            avatar(for: profile)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayHandle(profile))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PawPalTheme.primaryText)
                    .lineLimit(1)
                if let display = profile.display_name?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !display.isEmpty, display != profile.username {
                    Text(display)
                        .font(.system(size: 12))
                        .foregroundStyle(PawPalTheme.tertiaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PawPalTheme.tertiaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func avatar(for profile: RemoteProfile) -> some View {
        let size: CGFloat = 48
        Group {
            if let urlString = profile.avatar_url,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: initial(for: profile, size: size)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                initial(for: profile, size: size)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let pet = featuredPets[profile.id] {
                petBadge(for: pet)
                    .offset(x: 3, y: 3)
            }
        }
    }

    private func initial(for profile: RemoteProfile, size: CGFloat) -> some View {
        let letter: String = {
            if let name = profile.display_name?.prefix(1), !name.isEmpty { return String(name) }
            if let name = profile.username?.prefix(1), !name.isEmpty { return String(name) }
            return "?"
        }()
        return Text(letter.uppercased())
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(PawPalTheme.accent, in: Circle())
    }

    /// Small featured-pet badge pinned to the bottom-right of the user
    /// avatar. Mirrors the treatment in ChatListView.threadRow so the
    /// two surfaces read as siblings.
    @ViewBuilder
    private func petBadge(for pet: RemotePet) -> some View {
        let badge: CGFloat = 22
        ZStack {
            if let urlStr = pet.avatar_url, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        petBadgeFallback(for: pet)
                    }
                }
                .frame(width: badge, height: badge)
                .clipShape(Circle())
            } else {
                petBadgeFallback(for: pet)
                    .frame(width: badge, height: badge)
            }
        }
        .overlay(Circle().stroke(Color.white, lineWidth: 2))
    }

    @ViewBuilder
    private func petBadgeFallback(for pet: RemotePet) -> some View {
        ZStack {
            Circle().fill(PawPalTheme.cardSoft)
            Text(speciesEmoji(for: pet.species ?? ""))
                .font(.system(size: 12))
        }
    }

    private func speciesEmoji(for species: String) -> String {
        switch species.lowercased() {
        case "dog":             return "🐶"
        case "cat":             return "🐱"
        case "rabbit", "bunny": return "🐰"
        case "bird":            return "🦜"
        case "fish":            return "🐟"
        case "hamster":         return "🐹"
        default:                return "🐾"
        }
    }

    /// Empty state — the viewer follows nobody yet, so there's nobody to
    /// DM. Point them at the 发现 tab to find people to follow first.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(PawPalTheme.tertiaryText)
            Text("先去关注一些朋友吧")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PawPalTheme.primaryText)
            Text("在发现页搜索好友并关注他们的宠物,就能在这里直接发消息了")
                .font(.system(size: 13))
                .foregroundStyle(PawPalTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    private func displayHandle(_ profile: RemoteProfile) -> String {
        if let username = profile.username?.trimmingCharacters(in: .whitespacesAndNewlines),
           !username.isEmpty {
            return "@\(username)"
        }
        if let name = profile.display_name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return "@\(String(profile.id.uuidString.prefix(8)))"
    }
}
