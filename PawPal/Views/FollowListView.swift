import SwiftUI
import UIKit

/// Follower / following lists surfaced from the Me profile stats row.
/// Before #46 the 粉丝 / 关注 cells were non-interactive — you could see
/// the counts but had no way to inspect who was actually in either set,
/// and by extension no way to reach those people except by guessing
/// their handle in the 发现 tab. This screen closes that gap: tap a
/// count, see the real list, message anyone on it with one more tap.
///
/// MVP scope:
///
///   * Two modes — `.following` (users I follow) and `.followers`
///     (users who follow me) — selected by `mode` on init, with a
///     segmented switcher at the top so the user can flip between
///     them without popping back.
///   * Rows are rendered from `RemoteProfile`. Each row shows the
///     avatar, handle, display name, and a "发消息" pill that opens a
///     DM via `ChatService.startConversation`.
///   * Tapping the row itself is a no-op for now — there's no
///     standalone user profile screen to push to (users are viewed via
///     their pet profiles). When that lands the row can push to it.
///   * Empty state is handled for each mode separately so the copy
///     matches: no following → prompts to discover; no followers →
///     encourages posting.
struct FollowListView: View {
    enum Mode: Hashable {
        case following
        case followers

        var title: String {
            switch self {
            case .following: "关注"
            case .followers: "粉丝"
            }
        }

        var emptyTitle: String {
            switch self {
            case .following: "还没有关注任何人"
            case .followers: "还没有粉丝"
            }
        }

        var emptyHint: String {
            switch self {
            case .following: "在发现页搜索好友并关注他们的宠物吧"
            case .followers: "发布动态让更多爱宠人士认识你"
            }
        }
    }

    let targetUserID: UUID
    /// The logged-in viewer. Needed to initiate a DM (one participant
    /// is the viewer, the other is the row's user) and to gate the
    /// "发消息" affordance — self rows don't get a DM button.
    let viewerUserID: UUID
    /// Forwarded to `ChatDetailView` when we push into a chat. Bindable
    /// so the detail view can read the current-user id / profile.
    @Bindable var authManager: AuthManager
    @State private var mode: Mode

    @StateObject private var followService = FollowService()
    /// Shared with the rest of the app so a featured-pet lookup here
    /// benefits from the same cached write policy (e.g. `updatePetAvatar`
    /// in `PetProfileView` reflects here on return) without a re-fetch.
    @ObservedObject private var petsService = PetsService.shared
    @State private var followingProfiles: [RemoteProfile] = []
    @State private var followerProfiles: [RemoteProfile] = []
    /// Pet-first pass (P0 #3): each row renders the user's first pet as
    /// a small corner badge on the avatar. Keyed by owner user id.
    /// Falls back to no badge when the user has no pets yet.
    @State private var featuredPets: [UUID: RemotePet] = [:]
    @State private var isLoading = false
    /// Tracks whether the initial parallel preload has finished. We
    /// preload both lists up front so that flipping between 关注 / 粉丝
    /// swaps the content instantly without showing a loading spinner
    /// (and without a visible layout jump) on the first switch.
    @State private var hasPreloaded = false
    /// Transient error surfaced at the top of the list. Clears on a
    /// successful reload.
    @State private var errorMessage: String?
    /// Thread we're about to push into once `startConversation`
    /// resolves. Using `navigationDestination(item:)` avoids juggling a
    /// NavigationPath — we just set this and SwiftUI pushes the detail.
    @State private var pendingThread: ChatThread?

    init(
        targetUserID: UUID,
        viewerUserID: UUID,
        authManager: AuthManager,
        initialMode: Mode = .following
    ) {
        self.targetUserID = targetUserID
        self.viewerUserID = viewerUserID
        self.authManager = authManager
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        VStack(spacing: 0) {
            modeSwitcher
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if isLoading && currentList.isEmpty {
                ProgressView()
                    .padding(.vertical, 60)
                    .frame(maxWidth: .infinity)
            } else if currentList.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Color(.systemBackground))
        // Keep the title stable across mode changes — letting it swap
        // between "关注" and "粉丝" each time you tap the segmented
        // switcher caused the nav bar to re-measure and contributed to
        // the visible "jump". The segmented pill below it is the source
        // of truth for which list you're looking at.
        .navigationTitle("关注列表")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await preloadBothIfNeeded()
        }
        .refreshable {
            await reloadCurrent()
        }
        .navigationDestination(item: $pendingThread) { thread in
            ChatDetailView(thread: thread, authManager: authManager)
        }
    }

    // MARK: - Segmented switcher

    private var modeSwitcher: some View {
        HStack(spacing: 0) {
            ForEach([Mode.following, Mode.followers], id: \.self) { option in
                Button {
                    if mode != option {
                        mode = option
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } label: {
                    Text(option.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(mode == option ? .white : PawPalTheme.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            mode == option
                                ? AnyShapeStyle(PawPalTheme.accent)
                                : AnyShapeStyle(Color.clear),
                            in: Capsule(style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(PawPalTheme.cardSoft, in: Capsule(style: .continuous))
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(currentList, id: \.id) { profile in
                    row(for: profile)
                    Divider()
                        .padding(.leading, 76)  // inset under avatar
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

            if profile.id != viewerUserID {
                Button {
                    Task { await openChat(with: profile) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("发消息")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(PawPalTheme.accent, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
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

    /// Small featured-pet badge anchored to the bottom-right of the
    /// user avatar. Shows the pet's photo when available, otherwise a
    /// species emoji on a cardSoft fill. A white ring keeps the badge
    /// legible against both light and photo-heavy avatar backgrounds.
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

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(PawPalTheme.tertiaryText)
            Text(mode.emptyTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PawPalTheme.primaryText)
            Text(mode.emptyHint)
                .font(.system(size: 13))
                .foregroundStyle(PawPalTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 60)
    }

    // MARK: - Data

    private var currentList: [RemoteProfile] {
        switch mode {
        case .following: followingProfiles
        case .followers: followerProfiles
        }
    }

    /// Loads both the following and followers lists in parallel on the
    /// first appearance. Running them concurrently means the user rarely
    /// has to wait twice, and — more importantly — flipping the
    /// segmented switcher after the initial load shows the target list
    /// immediately instead of briefly flashing a ProgressView (which was
    /// the source of the perceived "layout jump" when switching modes).
    private func preloadBothIfNeeded() async {
        guard !hasPreloaded else { return }
        isLoading = true
        errorMessage = nil
        async let following = followService.loadFollowingProfiles(for: targetUserID)
        async let followers = followService.loadFollowerProfiles(for: targetUserID)
        let (fwg, fws) = await (following, followers)
        followingProfiles = fwg
        followerProfiles = fws
        isLoading = false
        hasPreloaded = true
        // Pet-first pass: fan-out one batched query for every user in
        // either list so the row avatars can render a featured-pet
        // badge in the bottom-right corner. Runs after the profile
        // lists resolve so we know the full set of owner IDs.
        let allIDs = Array(Set(fwg.map(\.id) + fws.map(\.id)))
        featuredPets = await petsService.loadFeaturedPets(for: allIDs)
    }

    /// Refresh path invoked by pull-to-refresh. Only reloads the
    /// currently-visible list — the invisible one stays as-is until its
    /// own pull-to-refresh or a fresh `.task`.
    private func reloadCurrent() async {
        errorMessage = nil
        switch mode {
        case .following:
            followingProfiles = await followService.loadFollowingProfiles(for: targetUserID)
        case .followers:
            followerProfiles = await followService.loadFollowerProfiles(for: targetUserID)
        }
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

    // MARK: - Chat navigation

    /// Starts (or re-opens) a DM with the tapped profile, then pushes
    /// `ChatDetailView`. Uses `ChatService.startConversation` so the
    /// canonical-ordered participants are respected and the row is
    /// idempotent against a pre-existing thread.
    private func openChat(with partner: RemoteProfile) async {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard let conversationID = await ChatService.shared.startConversation(
            userA: viewerUserID,
            userB: partner.id
        ) else {
            errorMessage = "无法创建聊天,请稍后再试"
            return
        }
        pendingThread = ChatThread(
            conversationID: conversationID,
            partnerID: partner.id,
            partnerProfile: partner,
            lastMessagePreview: nil,
            lastMessageAt: nil,
            createdAt: Date()
        )
    }
}
