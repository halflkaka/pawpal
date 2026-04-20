import SwiftUI
import MapKit

/// Full detail view for a single playdate. Four stacked slots:
///   1. Header strip (stacked pet avatars + status pill)
///   2. Time + location block (map snapshot post-accept only)
///   3. Message card (if message != nil && !isEmpty)
///   4. Contextual actions row (accept/decline/withdraw/cancel)
///
/// Copy + behaviour per §5.3 / §7 of
/// `docs/sessions/2026-04-18-pm-playdates-mvp-execution.md`.
struct PlaydateDetailView: View {
    let playdate: RemotePlaydate
    let proposerPet: RemotePet?
    let inviteePet: RemotePet?
    /// Current viewer — drives the actions row (viewer is proposer?
    /// invitee? neither?).
    let currentUserID: UUID?
    /// Optional so callers that don't already have an `AuthManager`
    /// handle (legacy test harnesses, future list surfaces) still
    /// compile; the "给主人发消息" pill hides when this is nil because
    /// `ChatDetailView` requires auth for its send path.
    var authManager: AuthManager?

    @Environment(\.dismiss) private var dismiss

    @State private var isMutating = false
    @State private var toastMessage: String?
    @State private var showingCancelConfirm = false
    /// Distinct confirmation for "取消整个系列" — kept separate from
    /// `showingCancelConfirm` so the dialog copy can be specific
    /// about the fan-out ("会取消剩余的所有场次") rather than the
    /// generic "另一方会收到通知" line for a single instance.
    @State private var showingCancelSeriesConfirm = false

    /// Presented when the viewer owns multiple pets in this playdate
    /// and needs to pick which one they're accepting for. Rare (a user
    /// with two pets, both invited to the same playdate) but possible
    /// enough to handle explicitly instead of silently picking the
    /// first row — silent picks would leave the other pet's
    /// participant row stuck on 'proposed' with no UX path to resolve
    /// it. Same picker also drives decline for consistency.
    @State private var pendingPetPickerAction: ParticipantAction?

    // Message-owner pill state. `isStartingChat` disables the button
    // and swaps the icon for a spinner while the `startConversation`
    // round-trip is in flight — a second tap during that window would
    // otherwise stack two nav pushes for the same conversation.
    // `pendingChatThread` drives the `.navigationDestination(item:)`
    // push once the thread is ready — same pattern used on
    // `PetProfileView` for owner chat.
    @State private var isStartingChat = false
    @State private var pendingChatThread: ChatThread?
    /// Presented when the playdate has multiple "other owners" (group
    /// playdate with 2 invitee owners if viewer is proposer, or 1
    /// co-invitee + proposer if viewer is an invitee). The pill stays
    /// single; the sheet lets the viewer pick which owner to DM.
    @State private var showingOwnerPicker = false

    /// Live cache read so status transitions done elsewhere (feed card
    /// accept tap, another device) flow into this view without a manual
    /// reload. Falls back to the initial `playdate` argument when the
    /// cache hasn't loaded this id yet.
    @ObservedObject private var playdateService = PlaydateService.shared

    private var current: RemotePlaydate {
        playdateService.playdates[playdate.id] ?? playdate
    }

    private var isProposer: Bool {
        currentUserID == current.proposer_user_id
    }

    /// True when the current viewer owns at least one invitee row on
    /// this playdate. Uses the junction embed as the source of truth
    /// so second invitees (group playdates — migration 028) resolve
    /// correctly; falls back to the legacy `invitee_user_id` equality
    /// when the embed isn't loaded.
    private var isInvitee: Bool {
        if current.playdate_participants != nil {
            return !viewerInviteeRows.isEmpty
        }
        return currentUserID == current.invitee_user_id
    }

    /// All participants from the junction embed (migration 028).
    /// Falls back to synthesising two rows from the legacy columns
    /// when the embed isn't loaded — this preserves the 2-avatar 1:1
    /// render path for cache hits that happened before the embed
    /// became standard.
    private var participants: [RemotePlaydateParticipant] {
        if let rows = current.playdate_participants, !rows.isEmpty {
            // Proposer first, then invitees, then by joined_at as a
            // secondary stable sort.
            return rows.sorted { lhs, rhs in
                if lhs.role != rhs.role {
                    return lhs.role == "proposer"
                }
                return lhs.joined_at < rhs.joined_at
            }
        }
        // Legacy fallback — synthesise two rows from the denormalised
        // columns. `joined_at` / `status` are best-effort here since
        // they aren't stored on the parent row.
        let proposerRow = RemotePlaydateParticipant(
            playdate_id: current.id,
            pet_id: current.proposer_pet_id,
            user_id: current.proposer_user_id,
            role: "proposer",
            status: current.status == .cancelled ? "cancelled" : "accepted",
            joined_at: current.created_at,
            pets: proposerPet,
            profiles: nil
        )
        let inviteeStatus: String = {
            switch current.status {
            case .completed: return "accepted"
            case .proposed:  return "proposed"
            case .accepted:  return "accepted"
            case .declined:  return "declined"
            case .cancelled: return "cancelled"
            }
        }()
        let inviteeRow = RemotePlaydateParticipant(
            playdate_id: current.id,
            pet_id: current.invitee_pet_id,
            user_id: current.invitee_user_id,
            role: "invitee",
            status: inviteeStatus,
            joined_at: current.created_at,
            pets: inviteePet,
            profiles: nil
        )
        return [proposerRow, inviteeRow]
    }

    /// Participant rows whose pet is owned by the current viewer —
    /// the set of pets the viewer can accept / decline "as". Usually
    /// length 1; can be 2 for a viewer whose two pets both got
    /// invited to the same group playdate.
    private var viewerInviteeRows: [RemotePlaydateParticipant] {
        guard let me = currentUserID else { return [] }
        return participants.filter { $0.role == "invitee" && $0.user_id == me }
    }

    /// True when at least one of the viewer's invitee rows is still
    /// in `proposed`. If every viewer-owned row is already resolved
    /// (accepted / declined / cancelled) the Accept/Decline buttons
    /// hide — responding twice from the same surface is noise.
    private var shouldShowInviteeActions: Bool {
        viewerInviteeRows.contains { $0.isProposed }
            || current.playdate_participants == nil  // 1:1 legacy fallback
    }

    /// Action to perform after the "为哪只毛孩接受邀请？" picker
    /// resolves. Stored as enum so the same picker surface serves
    /// both paths (accept + decline).
    enum ParticipantAction: Identifiable {
        case accept
        case decline
        var id: String {
            switch self {
            case .accept:  return "accept"
            case .decline: return "decline"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerStrip
                timeLocationBlock
                messageCard
                primaryActionsRow
                if shouldShowMessageOwnerPill {
                    // Lives inside the VStack's 16pt horizontal padding
                    // so the pill aligns edge-to-edge with the
                    // accept / decline / cancel buttons above and
                    // below. No extra padding needed on the pill
                    // itself — `frame(maxWidth: .infinity)` fills the
                    // inset width.
                    messageOwnerPill
                }
                cancelActionsRow
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(PawPalBackground())
        .navigationTitle("遛弯详情")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "确定要取消这次遛弯吗？",
            isPresented: $showingCancelConfirm,
            titleVisibility: .visible
        ) {
            Button("取消约会", role: .destructive) {
                Task { await cancel() }
            }
            Button("返回", role: .cancel) { }
        } message: {
            Text("另一方会收到通知")
        }
        .confirmationDialog(
            "取消整个系列约玩？",
            isPresented: $showingCancelSeriesConfirm,
            titleVisibility: .visible
        ) {
            Button("取消整个系列", role: .destructive) {
                Task { await cancelSeries() }
            }
            Button("返回", role: .cancel) { }
        } message: {
            Text("会取消剩余未开始的所有场次，另一方会收到通知。已结束或已拒绝的场次不受影响。")
        }
        // Per-pet picker presented when the viewer owns multiple
        // invitee rows on this playdate (two pets invited to the same
        // group playdate). `.sheet(item:)` re-renders per action kind
        // so tapping Accept then Decline swaps the sheet copy cleanly
        // instead of caching the first presentation's button.
        .sheet(item: $pendingPetPickerAction) { action in
            ParticipantPetPickerSheet(
                action: action,
                rows: viewerInviteeRows
            ) { chosen in
                pendingPetPickerAction = nil
                Task {
                    switch action {
                    case .accept:  await accept(petID: chosen.pet_id)
                    case .decline: await decline(petID: chosen.pet_id)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        // Owner picker — only presented for group playdates where the
        // "other side" resolves to more than one owner. `.confirmation`
        // would feel cramped once we include the disambiguating pet
        // name, so a compact sheet with owner rows reads better.
        .confirmationDialog(
            "给哪位主人发消息？",
            isPresented: $showingOwnerPicker,
            titleVisibility: .visible
        ) {
            ForEach(otherOwners) { owner in
                Button(ownerPickerLabel(for: owner)) {
                    Task { await startChat(with: owner) }
                }
            }
            Button("取消", role: .cancel) { }
        }
        // Chat push — populated by `startChat(with:)` after
        // `ChatService.startConversation` resolves. Mirrors the
        // `PetProfileView.pendingChatThread` wiring (see
        // `PetProfileView.swift:181`) so the two owner-DM entry points
        // use the same nav mechanic.
        .navigationDestination(item: $pendingChatThread) { thread in
            if let authManager {
                ChatDetailView(thread: thread, authManager: authManager)
            }
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
    }

    // MARK: - Header strip

    private var headerStrip: some View {
        VStack(spacing: 14) {
            // Horizontal scroll of every participant (migration 028).
            // For 1:1 playdates this shows 2 cells; for group playdates
            // it shows 3. Each cell renders the avatar, name, a
            // per-pet status chip (source of truth = the junction
            // `status`, which can differ from the top-level aggregate
            // while invitees are independently responding), and a
            // "发起人" badge on the proposer row.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(participants, id: \.id) { row in
                        participantCell(row: row)
                    }
                }
                .padding(.horizontal, 4)
            }

            // Top-level aggregate status pill — still useful as the
            // "big picture" state, even though the per-pet chips above
            // are authoritative for group playdates.
            statusPill

            // "proposer 约了 invitee 遛弯" title. For 3-pet group
            // playdates this collapses to "proposer 和 朋友们 遛弯" so
            // the title doesn't overflow with a comma-joined list.
            Text(titleText)
                .font(PawPalFont.rounded(size: 18, weight: .bold))
                .foregroundStyle(PawPalTheme.primaryText)
                .multilineTextAlignment(.center)

            // Series membership chip (migration 027). Only shown when
            // this row belongs to a weekly-repeat series — orients the
            // user to "this is one of 4" and primes them for the
            // series cancel action below.
            if let seq = current.series_sequence, current.isSeriesInstance {
                seriesChip(sequence: seq)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: PawPalRadius.xxl, style: .continuous)
                .fill(PawPalTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PawPalRadius.xxl, style: .continuous)
                .stroke(PawPalTheme.hairline, lineWidth: 0.5)
        )
        .shadow(color: PawPalTheme.softShadow, radius: 12, y: 2)
    }

    /// One cell inside the horizontal participant scroll. The pet
    /// reference comes from three places in priority order:
    ///   1. The junction embed (`row.pets`) when the embed was
    ///      fetched — always present for fresh fetches.
    ///   2. `proposerPet` / `inviteePet` when the row corresponds to
    ///      one of the legacy denormalised ids (1:1 fallback path).
    ///   3. A plain avatar placeholder otherwise (third invitee on
    ///      a group playdate that hasn't been re-fetched yet).
    @ViewBuilder
    private func participantCell(row: RemotePlaydateParticipant) -> some View {
        let pet = resolvePet(for: row)
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                avatar(for: pet, size: 64)
                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
                // Small "发起人" badge pinned to the proposer's
                // avatar. Absence of the badge implies invitee — we
                // don't clutter every invitee cell with a redundant
                // label.
                if row.isProposerRow {
                    Text("发起人")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(PawPalTheme.accent, in: Capsule())
                        .overlay(Capsule().stroke(Color.white, lineWidth: 1.5))
                        .offset(x: 4, y: -4)
                }
            }

            Text(pet?.name ?? "毛孩子")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
                .lineLimit(1)

            participantStatusChip(statusRaw: row.status)
        }
        .frame(width: 96)
    }

    /// Resolves the `RemotePet` for a participant row using embed →
    /// legacy args → nil fallback. Keeping this logic in one place
    /// avoids the caller-side ternary at every avatar site.
    private func resolvePet(for row: RemotePlaydateParticipant) -> RemotePet? {
        if let embedded = row.pets { return embedded }
        if row.pet_id == current.proposer_pet_id { return proposerPet }
        if row.pet_id == current.invitee_pet_id { return inviteePet }
        return nil
    }

    /// Per-pet status chip shown under each participant avatar. Uses
    /// the same tint family as the top-level `statusPill` so the two
    /// surfaces read consistently. Mapping mirrors the string values
    /// documented on the junction table (see migration 028).
    @ViewBuilder
    private func participantStatusChip(statusRaw: String) -> some View {
        let info = participantStatusInfo(statusRaw)
        HStack(spacing: 4) {
            Circle()
                .fill(info.tint)
                .frame(width: 5, height: 5)
            Text(info.label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(info.tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(info.tint.opacity(0.14), in: Capsule())
    }

    private func participantStatusInfo(_ raw: String) -> (label: String, tint: Color) {
        switch raw {
        case "accepted":  return ("已接受", PawPalTheme.mint)
        case "declined":  return ("已婉拒", PawPalTheme.secondaryText)
        case "cancelled": return ("已取消", PawPalTheme.secondaryText)
        case "proposed":  return ("待回应", PawPalTheme.amber)
        default:          return (raw, PawPalTheme.secondaryText)
        }
    }

    @ViewBuilder
    private func avatar(for pet: RemotePet?, size: CGFloat) -> some View {
        if let pet {
            PawPalAvatar(
                emoji: speciesEmoji(for: pet.species ?? ""),
                imageURL: pet.avatar_url,
                size: size,
                dogBreed: pet.species
            )
        } else {
            Circle()
                .fill(PawPalTheme.cardSoft)
                .frame(width: size, height: size)
                .overlay(Text("🐾").font(.system(size: size * 0.42)))
        }
    }

    /// Compact chip under the title marking this row as part of a
    /// series (migration 027). Uses the warm amber tone — distinct
    /// from the status pill's green/orange family — so it reads as
    /// informational rather than actionable.
    private func seriesChip(sequence: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "repeat")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(PawPalTheme.amber)
            Text("系列约玩 · 第 \(sequence) 场 / 共 4 场")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(PawPalTheme.amber.opacity(0.14), in: Capsule())
    }

    private var statusPill: some View {
        let info = statusInfo(current.status)
        return HStack(spacing: 6) {
            Circle()
                .fill(info.tint)
                .frame(width: 6, height: 6)
            Text(info.label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(info.tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(info.tint.opacity(0.14), in: Capsule())
    }

    private var titleText: String {
        // Proposer name comes from the junction row when the embed is
        // available — falls back to the legacy argument otherwise.
        let proposerRow = participants.first(where: { $0.isProposerRow })
        let proposerName = proposerRow?.pets?.name ?? proposerPet?.name ?? "毛孩子"

        let inviteeRows = participants.filter { $0.isInviteeRow }
        if inviteeRows.count >= 2 {
            // Group playdate — avoid a crowded "A 约了 B、C 遛弯" and
            // say "A 和 朋友们 遛弯" instead. The participant scroll
            // above already shows exactly who's going.
            return "\(proposerName) 和 朋友们 遛弯"
        }
        let inviteeName = inviteeRows.first?.pets?.name
            ?? inviteePet?.name
            ?? "毛孩子"
        return "\(proposerName) 约了 \(inviteeName) 遛弯"
    }

    // MARK: - Time + location block

    private var timeLocationBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PawPalTheme.accent)
                    .frame(width: 22, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatWhen(current.scheduled_at))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(PawPalTheme.primaryText)
                    Text(formatFullDate(current.scheduled_at))
                        .font(.system(size: 12))
                        .foregroundStyle(PawPalTheme.secondaryText)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PawPalTheme.accent)
                    .frame(width: 22, alignment: .leading)
                Text(locationDisplay)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PawPalTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if shouldShowMap, let coord = coord() {
                mapSnapshot(coord: coord)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: PawPalRadius.xxl, style: .continuous)
                .fill(PawPalTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PawPalRadius.xxl, style: .continuous)
                .stroke(PawPalTheme.hairline, lineWidth: 0.5)
        )
        .shadow(color: PawPalTheme.softShadow, radius: 12, y: 2)
    }

    private var shouldShowMap: Bool {
        current.status == .accepted && coord() != nil
    }

    private func coord() -> CLLocationCoordinate2D? {
        guard let lat = current.location_lat, let lng = current.location_lng else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// Pre-accept: hide the full address + slice at the last 区/县/市.
    /// Fallback "对方的附近" if no slicer token matches. Post-accept:
    /// show the full name.
    private var locationDisplay: String {
        if current.status == .accepted {
            return current.location_name
        }
        return "在 \(districtSlice(from: current.location_name))"
    }

    private func districtSlice(from raw: String) -> String {
        // Scan from the end for the last 区 / 县 / 市 terminator so
        // "上海市徐汇区" resolves to "上海市徐汇区" (cleanest chunk),
        // "北京海淀区中关村西路" resolves to "海淀区" etc.
        let tokens: [Character] = ["区", "县", "市"]
        guard let endIdx = raw.indices.reversed().first(where: { tokens.contains(raw[$0]) }) else {
            return "对方的附近"
        }
        // Walk backwards to the nearest comma / space / slash / 市 boundary
        // so we get a compact district string rather than the whole address.
        let delimiters: Set<Character> = [",", "，", " ", "·", "/", "-"]
        var startIdx = raw.startIndex
        var cursor = endIdx
        while cursor > raw.startIndex {
            let prev = raw.index(before: cursor)
            if delimiters.contains(raw[prev]) {
                startIdx = cursor
                break
            }
            cursor = prev
        }
        let slice = raw[startIdx...endIdx]
        let trimmed = slice.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "对方的附近" : String(trimmed)
    }

    @ViewBuilder
    private func mapSnapshot(coord: CLLocationCoordinate2D) -> some View {
        let region = MKCoordinateRegion(
            center: coord,
            latitudinalMeters: 300,
            longitudinalMeters: 300
        )
        Map(initialPosition: .region(region)) {
            Marker("", coordinate: coord)
                .tint(PawPalTheme.accent)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .allowsHitTesting(false)
    }

    // MARK: - Message card

    @ViewBuilder
    private var messageCard: some View {
        if let message = current.message, !message.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PawPalTheme.accent)
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(PawPalTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: PawPalRadius.xxl, style: .continuous)
                    .fill(PawPalTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PawPalRadius.xxl, style: .continuous)
                    .stroke(PawPalTheme.hairline, lineWidth: 0.5)
            )
            .shadow(color: PawPalTheme.softShadow, radius: 12, y: 2)
        }
    }

    // MARK: - Actions row
    //
    // Split into two halves so the "给主人发消息" pill can slot
    // between them: accept/decline on top, pill, then withdraw /
    // cancel / series-cancel below. Keeps the primary affirmative
    // response (accept) closest to where the viewer's eye lands after
    // reading the message card, and the destructive cancel action
    // furthest down.

    /// Primary affirmative action row — accept + decline buttons when
    /// the viewer still has a pending invitee row. Empty for every
    /// other state; the proposer's withdraw lives in `cancelActionsRow`
    /// instead so it stays visually grouped with the accepted-state
    /// cancel action.
    @ViewBuilder
    private var primaryActionsRow: some View {
        if current.status == .proposed, isInvitee, shouldShowInviteeActions {
            HStack(spacing: 12) {
                declineButton
                acceptButton
            }
        }
    }

    /// Destructive / withdrawal affordances — withdraw (proposer on a
    /// proposed row), cancel (proposer or invitee on an accepted row),
    /// or the series-aware menu variant on series instances.
    @ViewBuilder
    private var cancelActionsRow: some View {
        switch current.status {
        case .proposed:
            if isProposer {
                if current.isSeriesInstance {
                    seriesCancelMenu(singleLabel: "仅撤回本次")
                } else {
                    withdrawButton
                }
            }
        case .accepted:
            if isProposer || isInvitee {
                if current.isSeriesInstance {
                    seriesCancelMenu(singleLabel: "仅取消本次")
                } else {
                    cancelButton
                }
            }
        case .declined, .cancelled, .completed:
            EmptyView()
        }
    }

    private var acceptButton: some View {
        Button {
            handleInviteeAction(.accept)
        } label: {
            Text("接受")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(PawPalTheme.gradientOrangeToSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: PawPalTheme.accent.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isMutating)
    }

    private var declineButton: some View {
        Button {
            handleInviteeAction(.decline)
        } label: {
            Text("拒绝")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(PawPalTheme.cardSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isMutating)
    }

    /// Routes Accept / Decline taps based on how many of the viewer's
    /// pets are still pending on this playdate:
    ///   - 0 pending (legacy 1:1 fallback): use the legacy id-less RPC.
    ///   - 1 pending: respond on that one row directly.
    ///   - 2 pending: present the picker — silently picking the first
    ///     would leave the other row stranded.
    private func handleInviteeAction(_ action: ParticipantAction) {
        let pending = viewerInviteeRows.filter { $0.isProposed }
        if pending.count > 1 {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            pendingPetPickerAction = action
            return
        }
        let petID = pending.first?.pet_id ?? viewerInviteeRows.first?.pet_id
        Task {
            switch action {
            case .accept:  await accept(petID: petID)
            case .decline: await decline(petID: petID)
            }
        }
    }

    private var withdrawButton: some View {
        Button {
            Task { await cancel() }
        } label: {
            Text("撤回邀请")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(PawPalTheme.cardSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isMutating)
    }

    private var cancelButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showingCancelConfirm = true
        } label: {
            Text("取消约会")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(PawPalTheme.cardSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isMutating)
    }

    /// Series-aware cancel affordance. The proposer and invitee both
    /// see the same two options — cancel just this instance, or
    /// cancel every future non-finalised row in the series. Each
    /// option funnels through its own `.confirmationDialog` so an
    /// accidental tap can't be destructive. Haptic on open is `.medium`
    /// matching the single-instance button.
    private func seriesCancelMenu(singleLabel: String) -> some View {
        Menu {
            Button(singleLabel, role: .destructive) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showingCancelConfirm = true
            }
            Button("取消整个系列", role: .destructive) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showingCancelSeriesConfirm = true
            }
        } label: {
            HStack(spacing: 8) {
                Text("取消约会")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(PawPalTheme.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(PawPalTheme.cardSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(isMutating)
    }

    // MARK: - Message owner pill

    /// Candidate "other owner" — one entry per distinct user_id on this
    /// playdate other than the viewer, whose participant row is still
    /// live (`proposed` or `accepted`). `cancelled` / `declined` owners
    /// are dropped — DMing someone who bailed out of the walk reads
    /// awkward and isn't what the pill is for.
    ///
    /// Comes from the `playdate_participants` embed when it's loaded;
    /// falls back to the legacy denormalised proposer / invitee columns
    /// otherwise (1:1 cache hits from before migration 028). The
    /// fallback path only ever yields one entry since pre-028 rows had
    /// exactly one "other side".
    private struct OtherOwner: Identifiable, Hashable {
        let userID: UUID
        let profile: RemoteProfile?
        /// A pet name to disambiguate multiple owners on the picker
        /// ("王小明 · 带着 豆豆") — for legacy fallbacks this can be nil.
        let petName: String?
        let petSpecies: String?
        let petAvatarURL: String?
        var id: UUID { userID }
    }

    /// Resolves the other-owner list using the junction embed when it's
    /// available, otherwise the legacy columns. Dedupes by user_id so
    /// a group playdate where one owner brought two pets only shows
    /// that owner once.
    private var otherOwners: [OtherOwner] {
        guard let me = currentUserID else { return [] }

        if let rows = current.playdate_participants, !rows.isEmpty {
            // Keep only live rows belonging to someone other than the
            // viewer. Order: proposer first, then invitees by
            // joined_at — matches the participant scroll above so the
            // picker list reads consistently with the avatars.
            let sorted = rows.sorted { lhs, rhs in
                if lhs.role != rhs.role { return lhs.role == "proposer" }
                return lhs.joined_at < rhs.joined_at
            }
            var seen = Set<UUID>()
            var out: [OtherOwner] = []
            for row in sorted {
                guard row.user_id != me else { continue }
                guard row.status == "proposed" || row.status == "accepted" else { continue }
                guard !seen.contains(row.user_id) else { continue }
                seen.insert(row.user_id)
                out.append(OtherOwner(
                    userID: row.user_id,
                    profile: row.profiles,
                    petName: row.pets?.name,
                    petSpecies: row.pets?.species,
                    petAvatarURL: row.pets?.avatar_url
                ))
            }
            return out
        }

        // Legacy fallback — synthesise a single "other owner" from the
        // denormalised columns. The top-level aggregate status gates
        // the same "live only" rule as the embed path.
        guard current.status == .proposed || current.status == .accepted else {
            return []
        }
        let otherID: UUID
        let otherPet: RemotePet?
        if me == current.proposer_user_id {
            otherID = current.invitee_user_id
            otherPet = inviteePet
        } else if me == current.invitee_user_id {
            otherID = current.proposer_user_id
            otherPet = proposerPet
        } else {
            return []
        }
        return [OtherOwner(
            userID: otherID,
            profile: nil,
            petName: otherPet?.name,
            petSpecies: otherPet?.species,
            petAvatarURL: otherPet?.avatar_url
        )]
    }

    /// Pill visibility — only surface for live playdates (`proposed` /
    /// `accepted`), when auth is wired, and when there's at least one
    /// valid other owner to message.
    private var shouldShowMessageOwnerPill: Bool {
        guard authManager != nil else { return false }
        guard current.status == .proposed || current.status == .accepted else {
            return false
        }
        return !otherOwners.isEmpty
    }

    /// Warm-accent full-width pill styled to match the DesignSystem
    /// primary CTA. Single button regardless of owner count — the tap
    /// handler branches between "open directly" (1) and "show picker"
    /// (>1) so the surface stays calm for the common 1:1 case.
    private var messageOwnerPill: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            handleMessageOwnerTap()
        } label: {
            HStack(spacing: 8) {
                if isStartingChat {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(isStartingChat ? "正在打开…" : "给主人发消息")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(PawPalTheme.gradientOrangeToSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: PawPalTheme.accent.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isStartingChat)
    }

    /// Label shown in the confirmation dialog when multiple other
    /// owners are present. Prefers the owner's display_name / username
    /// from the profile embed, falling back to a truncated user id so
    /// the row is never empty. Appends the associated pet name when
    /// we have one so "王小明" vs "李华" are easy to tell apart in a
    /// group playdate.
    private func ownerPickerLabel(for owner: OtherOwner) -> String {
        let name: String = {
            if let display = owner.profile?.display_name?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !display.isEmpty {
                return display
            }
            if let handle = owner.profile?.username?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !handle.isEmpty {
                return "@\(handle)"
            }
            return "用户 \(String(owner.userID.uuidString.prefix(4)))"
        }()
        if let petName = owner.petName, !petName.isEmpty {
            return "\(name) · \(petName) 的主人"
        }
        return name
    }

    /// Routes based on other-owner count: 1 → start the chat directly;
    /// >1 → present the picker so the viewer chooses who to DM.
    private func handleMessageOwnerTap() {
        let owners = otherOwners
        guard !owners.isEmpty else { return }
        if owners.count == 1 {
            Task { await startChat(with: owners[0]) }
        } else {
            showingOwnerPicker = true
        }
    }

    /// Find-or-create the conversation with `owner`, resolve the
    /// partner profile if the embed didn't include it, then populate
    /// `pendingChatThread` to trigger the nav push. Mirrors the
    /// `PetProfileView.startChatWithOwner` flow at line 748 so the two
    /// entry points stay consistent.
    private func startChat(with owner: OtherOwner) async {
        guard !isStartingChat, let viewerID = currentUserID else { return }
        guard viewerID != owner.userID else { return }
        guard authManager != nil else { return }
        isStartingChat = true
        defer { isStartingChat = false }

        async let convoTask = ChatService.shared.startConversation(
            userA: viewerID,
            userB: owner.userID
        )
        let conversationID = await convoTask

        // Resolve the partner profile — prefer the embed we already
        // have, otherwise go fetch so the chat header isn't blank on
        // first paint. Sequential (not parallel) because this only
        // runs when the conversation id successfully resolved; parallel
        // profile fetches on failed conversation creation is wasted
        // work.
        let partnerProfile: RemoteProfile?
        if let embedded = owner.profile {
            partnerProfile = embedded
        } else {
            partnerProfile = try? await ProfileService().loadProfile(for: owner.userID)
        }

        guard let conversationID else {
            showToast("无法创建聊天,请稍后再试")
            return
        }
        pendingChatThread = ChatThread(
            conversationID: conversationID,
            partnerID: owner.userID,
            partnerProfile: partnerProfile,
            lastMessagePreview: nil,
            lastMessageAt: nil,
            createdAt: Date()
        )
    }

    // MARK: - Mutation handlers

    /// Accept the invitation on behalf of one of the viewer's pets.
    /// Prefers the migration-028 RPC (`acceptInvitation`) when a pet
    /// id is supplied — this is the only path that respects per-pet
    /// status on group playdates. Falls back to the legacy id-less
    /// RPC for 1:1 rows whose embed never loaded.
    private func accept(petID: UUID? = nil) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let ok: Bool
        if let petID {
            ok = await playdateService.acceptInvitation(playdateID: current.id, petID: petID)
        } else {
            ok = await playdateService.accept(current.id)
        }
        if ok {
            showToast("已确认 · 我们会提前提醒你")
        } else {
            showToast(playdateService.errorMessage ?? "操作失败，请稍后再试")
        }
    }

    /// Decline the invitation on behalf of one of the viewer's pets.
    /// For group playdates with a second pending invitee the parent
    /// playdate status stays `proposed` (only the individual row goes
    /// to `declined`), so we don't auto-dismiss — the viewer can
    /// still see the other pets' status.
    private func decline(petID: UUID? = nil) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        let ok: Bool
        if let petID {
            ok = await playdateService.declineInvitation(playdateID: current.id, petID: petID)
        } else {
            ok = await playdateService.decline(current.id)
        }
        if ok {
            // Only pop when the whole playdate is now declined — for
            // group playdates with other pending rows the detail
            // stays useful.
            if current.status == .declined {
                dismiss()
            } else {
                showToast("已婉拒")
            }
        } else {
            showToast(playdateService.errorMessage ?? "操作失败，请稍后再试")
        }
    }

    /// Proposer-side cancel. Goes through the new
    /// `cancelAsProposer` RPC which cascades every still-pending
    /// participant row to `cancelled` in a single trigger-guarded
    /// transaction. Legacy `cancel(_:)` remains on the service for
    /// non-proposer withdraw paths that don't fan out.
    private func cancel() async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        let ok: Bool
        if isProposer {
            ok = await playdateService.cancelAsProposer(playdateID: current.id)
        } else {
            ok = await playdateService.cancel(current.id)
        }
        if ok {
            showToast("已取消")
            // Let the toast breathe, then pop back.
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        } else {
            showToast(playdateService.errorMessage ?? "操作失败，请稍后再试")
        }
    }

    /// Cancels every future non-finalised row in this series via
    /// `PlaydateService.cancelSeries`. Past instances and rows already
    /// in `declined`/`cancelled`/`completed` are intentionally left
    /// alone — see the service-layer comment for the predicate.
    private func cancelSeries() async {
        guard !isMutating, let seriesID = current.series_id else { return }
        isMutating = true
        defer { isMutating = false }
        let ok = await playdateService.cancelSeries(seriesID: seriesID)
        if ok {
            showToast("已取消整个系列")
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        } else {
            showToast(playdateService.errorMessage ?? "操作失败，请稍后再试")
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    // MARK: - Formatting helpers

    private func statusInfo(_ status: RemotePlaydate.Status) -> (label: String, tint: Color) {
        switch status {
        case .proposed:   return ("邀请中", PawPalTheme.amber)
        case .accepted:   return ("已确认", PawPalTheme.mint)
        case .declined:   return ("对方婉拒了", PawPalTheme.secondaryText)
        case .cancelled:  return ("已取消", PawPalTheme.secondaryText)
        case .completed:  return ("已完成", PawPalTheme.secondaryText)
        }
    }

    private func formatWhen(_ date: Date) -> String {
        // "周六下午 3:00" / "明天早上 10:30" style — weekday + rough
        // segment + time.
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let segment: String
        switch hour {
        case ..<12: segment = "早上"
        case 12..<18: segment = "下午"
        default: segment = "晚上"
        }
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "zh_CN")
        weekdayFormatter.dateFormat = "EEEE"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_CN")
        timeFormatter.dateFormat = "HH:mm"
        return "\(weekdayFormatter.string(from: date))\(segment) · \(timeFormatter.string(from: date))"
    }

    private func formatFullDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: date)
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

// MARK: - Pet picker sheet
//
// Presented from `PlaydateDetailView` when the current viewer owns
// more than one invitee row on the same playdate (group playdate — a
// user whose Pet A and Pet B both got invited). Same surface serves
// both Accept and Decline paths so the viewer's two taps converge on
// one visual pattern; copy swaps on the passed `action`.
private struct ParticipantPetPickerSheet: View {
    let action: PlaydateDetailView.ParticipantAction
    let rows: [RemotePlaydateParticipant]
    let onPick: (RemotePlaydateParticipant) -> Void

    @Environment(\.dismiss) private var dismiss

    private var title: String {
        switch action {
        case .accept:  return "为哪只毛孩接受邀请？"
        case .decline: return "为哪只毛孩婉拒？"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(rows, id: \.id) { row in
                    Button {
                        onPick(row)
                    } label: {
                        HStack(spacing: 12) {
                            if let pet = row.pets {
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
                                    .overlay(Text("🐾"))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.pets?.name ?? "毛孩子")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(PawPalTheme.primaryText)
                                Text(statusLabel(row.status))
                                    .font(.system(size: 12))
                                    .foregroundStyle(PawPalTheme.secondaryText)
                            }
                            Spacer()
                            // Dim rows whose status already settled —
                            // tapping still fires `onPick`, but the
                            // RPC will no-op server-side (the
                            // participant row is already `accepted` /
                            // `declined`).
                            if !row.isProposed {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(PawPalTheme.secondaryText)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func statusLabel(_ raw: String) -> String {
        switch raw {
        case "accepted":  return "已接受"
        case "declined":  return "已婉拒"
        case "cancelled": return "已取消"
        case "proposed":  return "待回应"
        default: return raw
        }
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
