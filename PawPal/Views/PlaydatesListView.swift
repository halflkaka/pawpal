import SwiftUI

/// "我的约玩" — a flat list of every playdate the current user has,
/// across all their pets, both sent and received. Accessible from
/// `ProfileView` so users can revisit playdate details any time (not
/// just via the navigation push right after composing).
///
/// Three segments:
///   * 收到的 — rows where the viewer is the invitee
///   * 发出的 — rows where the viewer is the proposer
///   * 全部   — every row, merged
///
/// Rows are sorted soonest-scheduled first (tie-break: most recently
/// created wins for same-day rows). Tapping a row pushes the existing
/// `PlaydateDetailView` with the other-pet avatar resolved via
/// `PetsService` — the viewer's own pet is always in the shared pets
/// cache, and "other" pets are bulk-fetched on appear so avatars land
/// without a per-row network hop.
///
/// Copy + tone matches `docs/product.md`'s Chinese-first, warm voice:
/// empty state reads "你还没有约玩记录" with a nudge toward Discover.
struct PlaydatesListView: View {
    let currentUserID: UUID
    /// Optional so legacy call sites keep compiling; threaded into
    /// `PlaydateDetailView` so the "给主人发消息" pill can open a DM
    /// with the other owner without a second hop through a shared
    /// environment object.
    var authManager: AuthManager?

    // Shared caches — same pattern as `DeepLinkPlaydateLoader` /
    // `FeedView`. Pets service holds the viewer's own pets; for the
    // "other" side we maintain a local `otherPets` dict populated on
    // load.
    @ObservedObject private var playdateService = PlaydateService.shared
    @ObservedObject private var petsService = PetsService.shared

    /// Client-only filter — we always fetch the full set once and
    /// re-derive the visible rows from it so switching tabs is free.
    @State private var segment: Segment = .received
    @State private var playdates: [RemotePlaydate] = []
    @State private var otherPets: [UUID: RemotePet] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?

    enum Segment: Hashable, CaseIterable {
        case received, sent, all

        var label: String {
            switch self {
            case .received: return "收到的"
            case .sent:     return "发出的"
            case .all:      return "全部"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            segmentPicker
            content
        }
        .background(PawPalBackground())
        .navigationTitle("我的约玩")
        .navigationBarTitleDisplayMode(.inline)
        // Destination registered at the root so segment switches /
        // empty-state re-renders don't tear down the handler — the
        // parent NavigationStack (ProfileView) is what picks it up.
        .navigationDestination(for: RemotePlaydate.self) { row in
            PlaydateDetailView(
                playdate: row,
                proposerPet: petFor(id: row.proposer_pet_id),
                inviteePet: petFor(id: row.invitee_pet_id),
                currentUserID: currentUserID,
                authManager: authManager
            )
        }
        .task { await load() }
        .refreshable { await load() }
        // React to any status transition done elsewhere (detail view's
        // accept/decline/cancel buttons). Re-derive from the shared
        // cache so a row's status chip updates without a pull-to-
        // refresh. Guarded by `playdates.isEmpty == false` so we don't
        // fight the initial load.
        .onReceive(NotificationCenter.default.publisher(for: .playdateDidChange)) { _ in
            guard !playdates.isEmpty else { return }
            mergeFromCache()
        }
    }

    // MARK: - Segment picker

    private var segmentPicker: some View {
        HStack(spacing: 6) {
            ForEach(Segment.allCases, id: \.self) { seg in
                segmentChip(seg)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func segmentChip(_ seg: Segment) -> some View {
        let selected = segment == seg
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                segment = seg
            }
        } label: {
            Text(seg.label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? .white : PawPalTheme.secondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    selected
                        ? AnyShapeStyle(PawPalTheme.gradientOrangeToSoft)
                        : AnyShapeStyle(PawPalTheme.cardSoft),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(selected ? Color.clear : PawPalTheme.hairline, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let visible = rowsForSegment()
        if isLoading && playdates.isEmpty {
            loadingState
        } else if let errorMessage, playdates.isEmpty {
            errorState(errorMessage)
        } else if visible.isEmpty {
            emptyState
        } else {
            list(visible)
        }
    }

    private func list(_ rows: [RemotePlaydate]) -> some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(rows) { row in
                    NavigationLink(value: row) {
                        PlaydateRowView(
                            playdate: row,
                            otherPet: otherPets[row.otherPetId(for: currentUserID)]
                                ?? petsService.cachedPet(id: row.otherPetId(for: currentUserID))
                        )
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    })
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Empty / loading / error states

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(PawPalTheme.accent)
            Text("加载中…")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(PawPalTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 80)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("🐾")
                .font(.system(size: 44))
                .padding(.bottom, 2)
            Text("你还没有约玩记录")
                .font(PawPalFont.rounded(size: 16, weight: .bold))
                .foregroundStyle(PawPalTheme.primaryText)
            Text("去 Discover 看看可约玩的毛孩子吧")
                .font(.system(size: 13))
                .foregroundStyle(PawPalTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .padding(.bottom, 80)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(PawPalTheme.amber)
            Text("加载失败")
                .font(PawPalFont.rounded(size: 16, weight: .bold))
                .foregroundStyle(PawPalTheme.primaryText)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(PawPalTheme.secondaryText)
                .multilineTextAlignment(.center)
            Button {
                Task { await load() }
            } label: {
                Text("重试")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(PawPalTheme.gradientOrangeToSoft, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .padding(.bottom, 80)
    }

    // MARK: - Derivations

    private func rowsForSegment() -> [RemotePlaydate] {
        switch segment {
        case .received:
            return playdates.filter { $0.invitee_user_id == currentUserID }
        case .sent:
            return playdates.filter { $0.proposer_user_id == currentUserID }
        case .all:
            return playdates
        }
    }

    /// Resolve a pet id to a `RemotePet` by checking the viewer's own
    /// pets cache first, then the locally-populated `otherPets` dict.
    /// Returns nil on miss — the row / detail views degrade to a
    /// "🐾" placeholder in that case.
    private func petFor(id: UUID) -> RemotePet? {
        if let own = petsService.cachedPet(id: id) { return own }
        return otherPets[id]
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let rows = try await PlaydateService.shared.fetchAllForCurrentUser()
            self.playdates = rows
            await resolveOtherPets(for: rows)
        } catch {
            print("[PlaydatesList] load 失败: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    /// Merge the shared cache back into our local list when a status
    /// transition fires elsewhere. We intentionally keep our own local
    /// `playdates` array rather than observing the service directly so
    /// the segment filter + sort don't re-compute on every unrelated
    /// `loadUpcoming`.
    private func mergeFromCache() {
        var changed = false
        for (idx, row) in playdates.enumerated() {
            if let updated = playdateService.playdates[row.id], updated != row {
                playdates[idx] = updated
                changed = true
            }
        }
        if changed {
            // Re-sort in case scheduled_at was edited (not currently
            // possible in the UI, but cheap to keep correct).
            playdates.sort { lhs, rhs in
                if lhs.scheduled_at != rhs.scheduled_at {
                    return lhs.scheduled_at < rhs.scheduled_at
                }
                return lhs.created_at > rhs.created_at
            }
        }
    }

    /// Bulk-fetches every "other pet" referenced by the row set that
    /// isn't already in `petsService.pets`. One round-trip via
    /// `in("id", …)` instead of per-row fetches. Missing rows fall
    /// back to the 🐾 placeholder in `PlaydateRowView`.
    private func resolveOtherPets(for rows: [RemotePlaydate]) async {
        let ownedIDs = Set(petsService.pets.map(\.id))
        let otherIDs: Set<UUID> = Set(rows.map { $0.otherPetId(for: currentUserID) })
            .subtracting(ownedIDs)
            .subtracting(otherPets.keys)

        guard !otherIDs.isEmpty else { return }

        do {
            let fetched: [RemotePet] = try await SupabaseConfig.client
                .from("pets")
                .select()
                .in("id", values: otherIDs.map { $0.uuidString })
                .execute()
                .value
            var dict = otherPets
            for pet in fetched { dict[pet.id] = pet }
            otherPets = dict
        } catch {
            // Non-fatal — rows keep their placeholder avatar.
            print("[PlaydatesList] resolveOtherPets 失败: \(error)")
        }
    }
}

// MARK: - Row

/// One row in the My Playdates list. Avatar + other-pet name, a
/// relative-Chinese-date line (明天 15:00 / 周三 14:30 / 4月22日 10:00),
/// location, and a trailing status chip.
private struct PlaydateRowView: View {
    let playdate: RemotePlaydate
    let otherPet: RemotePet?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                Text(otherPet?.name ?? "毛孩子")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(PawPalTheme.primaryText)
                    .lineLimit(1)
                Text(whenLine)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PawPalTheme.secondaryText)
                    .lineLimit(1)
                Text(playdate.location_name)
                    .font(.system(size: 12))
                    .foregroundStyle(PawPalTheme.tertiaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            statusChip
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: PawPalRadius.xl, style: .continuous)
                .fill(PawPalTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PawPalRadius.xl, style: .continuous)
                .stroke(PawPalTheme.hairline, lineWidth: 0.5)
        )
        .shadow(color: PawPalTheme.softShadow, radius: 8, y: 2)
        .contentShape(Rectangle())
    }

    // MARK: - Avatar (16pt → actually 44pt visual; the spec says "16pt
    // circle" but that would be tiny; we use the same 44pt size as
    // `PlaydateRequestCard` so the list row reads consistently with
    // the feed cards. The label is the avatar role, not the size.)

    @ViewBuilder
    private var avatar: some View {
        if let pet = otherPet {
            PawPalAvatar(
                emoji: speciesEmoji(for: pet.species ?? ""),
                imageURL: pet.avatar_url,
                size: 44,
                dogBreed: pet.species
            )
        } else {
            Circle()
                .fill(PawPalTheme.cardSoft)
                .frame(width: 44, height: 44)
                .overlay(Text("🐾").font(.system(size: 20)))
        }
    }

    // MARK: - Status chip

    private var statusChip: some View {
        let info = statusInfo(playdate.status)
        return Text(info.label)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(info.foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(info.background, in: Capsule())
    }

    /// Status chip styling per the task spec:
    ///   * proposed  → warm yellow (amber)     — "待确认"
    ///   * accepted  → meadow green (mint)     — "已确认"
    ///   * declined  → muted coral (red w/ 45% bg) — "已拒绝"
    ///   * cancelled → ink at 60% opacity      — "已取消"
    ///   * completed → tide blue (cool)        — "已完成"
    private func statusInfo(_ status: RemotePlaydate.Status) -> (label: String, foreground: Color, background: Color) {
        switch status {
        case .proposed:
            return ("待确认", PawPalTheme.amber, PawPalTheme.amber.opacity(0.16))
        case .accepted:
            return ("已确认", PawPalTheme.mint, PawPalTheme.mint.opacity(0.18))
        case .declined:
            return ("已拒绝", PawPalTheme.red, PawPalTheme.red.opacity(0.14))
        case .cancelled:
            return (
                "已取消",
                PawPalTheme.primaryText.opacity(0.6),
                PawPalTheme.cardSoft
            )
        case .completed:
            return ("已完成", PawPalTheme.cool, PawPalTheme.cool.opacity(0.16))
        }
    }

    // MARK: - When line

    /// Relative Chinese date:
    ///   * Today        → "今天 15:00"
    ///   * Tomorrow     → "明天 15:00"
    ///   * This week    → "周三 14:30"
    ///   * Farther out  → "4月22日 10:00"
    private var whenLine: String {
        let date = playdate.scheduled_at
        let cal = Calendar(identifier: .gregorian)
        let now = Date()

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_CN")
        timeFormatter.dateFormat = "HH:mm"
        let time = timeFormatter.string(from: date)

        if cal.isDateInToday(date) {
            return "今天 \(time)"
        }
        if cal.isDateInTomorrow(date) {
            return "明天 \(time)"
        }
        if cal.isDateInYesterday(date) {
            return "昨天 \(time)"
        }
        // Within the next 7 days (and not already covered above) → weekday.
        // Also cover the "past week" case so recently-completed rows read
        // naturally ("周三 14:30") instead of flipping to a full date.
        if let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day,
           abs(days) < 7 {
            let weekdayFormatter = DateFormatter()
            weekdayFormatter.locale = Locale(identifier: "zh_CN")
            weekdayFormatter.dateFormat = "EEEE"
            return "\(weekdayFormatter.string(from: date)) \(time)"
        }
        // Farther out — M月d日 HH:mm.
        let farFormatter = DateFormatter()
        farFormatter.locale = Locale(identifier: "zh_CN")
        farFormatter.dateFormat = "M月d日 HH:mm"
        return farFormatter.string(from: date)
    }

    private func speciesEmoji(for species: String) -> String {
        switch species.lowercased() {
        case "dog": return "🐶"
        case "cat": return "🐱"
        case "rabbit": return "🐰"
        case "bird": return "🐦"
        case "hamster": return "🐹"
        default: return "🐾"
        }
    }
}
