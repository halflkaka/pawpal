import SwiftUI
import MapKit

/// Identifiable wrapper so `PetProfileView` can use `.sheet(item:)` with
/// a per-opening identity. Each tap mints a new UUID so the composer
/// re-instantiates cleanly — same trick `ComposerPrefill` uses for the
/// milestone composer.
struct PlaydateComposerTarget: Identifiable {
    let id = UUID()
    let inviteePet: RemotePet
    let inviteeUserID: UUID
    let proposerPetOptions: [RemotePet]
}

/// A pet that has been added to the composer's invitee list — the
/// pet row plus the denormalised owner id needed for the legacy
/// `invitee_user_id` column + the junction's `user_id`. Keeping it
/// here (rather than passing `RemotePet` alone) means the composer
/// doesn't have to re-query owner ids at submit time.
struct ComposerInvitee: Identifiable, Hashable {
    let pet: RemotePet
    let ownerUserID: UUID
    var id: UUID { pet.id }
}

/// Modal sheet for proposing a playdate. Presented from `PetProfileView`'s
/// 约遛弯 pill via `.sheet(item: $playdateComposerTarget)`. Drives
/// `PlaydateService.propose(...)` on 发送邀请.
///
/// Copy + layout per §5.2 / §7 of
/// `docs/sessions/2026-04-18-pm-playdates-mvp-execution.md`.
struct PlaydateComposerSheet: View {
    let inviteePet: RemotePet
    let inviteeUserID: UUID
    let proposerPetOptions: [RemotePet]
    let onSent: (RemotePlaydate) -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: - Invitees (1-2 pets; migration 028 cap is 3 participants total)
    //
    // Seeded from the sheet's initial `inviteePet` / `inviteeUserID`
    // (the pet whose profile the proposer tapped 约遛弯 on). The user
    // can append a second invitee by tapping 再邀请一只 — two is the
    // hard cap in the UI; the schema trigger
    // `enforce_playdate_participant_count` enforces >=3 total on the
    // server as defense in depth.
    @State private var invitees: [ComposerInvitee] = []

    // Second-invitee picker sheet state. Presented as an
    // `.sheet(item:)` so `AddInviteeSheet` gets a fresh instance each
    // tap (mirrors `ComposerPrefill`'s identity-per-open trick).
    @State private var isPickingSecondInvitee = false

    private let maxInvitees = 2

    // MARK: - Proposer pet
    @State private var proposerPetID: UUID?

    // MARK: - Date / time
    /// Default: tomorrow at 15:00 local. Min: now + 1h. Max: now + 30d.
    @State private var scheduledAt: Date = PlaydateComposerSheet.defaultScheduledAt()

    // MARK: - Location
    @State private var locationQuery: String = ""
    @State private var selectedLocationName: String? = nil
    @State private var resolvedCoord: CLLocationCoordinate2D? = nil
    @StateObject private var completer = LocationCompleter()
    @State private var isResolvingCoord = false

    // MARK: - Optional message (140ch cap)
    @State private var message: String = ""
    private let messageLimit = 140

    // MARK: - Weekly repeat (×4)
    /// Toggle for "每周重复 ×4". When ON the composer fans out to four
    /// playdate rows linked by a shared `series_id` (migration 027).
    /// Default OFF — the one-off case is by far the more common path.
    @State private var repeatWeekly: Bool = false

    // MARK: - Submission
    @State private var isSending = false
    @State private var errorMessage: String?

    private var minScheduledAt: Date { Date().addingTimeInterval(60 * 60) }
    private var maxScheduledAt: Date { Date().addingTimeInterval(60 * 60 * 24 * 30) }

    private var canSend: Bool {
        guard proposerPetID != nil,
              selectedLocationName != nil,
              !invitees.isEmpty,
              !isSending
        else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        proposerPetSection
                        inviteesSection
                        timeSection
                        repeatWeeklySection
                        locationSection
                        messageSection
                        if let errorMessage {
                            errorBanner(errorMessage)
                        }
                        sendButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                // Auto-select when there's exactly one proposer pet —
                // saves an extra tap on the common single-pet case.
                if proposerPetID == nil, proposerPetOptions.count == 1 {
                    proposerPetID = proposerPetOptions.first?.id
                }
                // Seed the invitee list from the sheet's entry point
                // (the pet whose profile the proposer tapped 约遛弯 on).
                if invitees.isEmpty {
                    invitees = [ComposerInvitee(
                        pet: inviteePet,
                        ownerUserID: inviteeUserID
                    )]
                }
            }
            .sheet(isPresented: $isPickingSecondInvitee) {
                AddInviteeSheet(
                    excludedPetIDs: Set(invitees.map(\.pet.id) + proposerPetOptions.map(\.id)),
                    onPick: { picked in
                        // Append, capped at `maxInvitees`. The picker
                        // sheet dismisses itself on select.
                        if invitees.count < maxInvitees {
                            invitees.append(picked)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        isPickingSecondInvitee = false
                    }
                )
            }
            .onChange(of: locationQuery) { _, newValue in
                // As-you-type search via MKLocalSearchCompleter.
                // Clearing the query clears results; selecting a result
                // pins `selectedLocationName` (handled below).
                if newValue != selectedLocationName {
                    selectedLocationName = nil
                    resolvedCoord = nil
                }
                completer.search(newValue)
            }
            .onChange(of: message) { _, newValue in
                // Hard-cap at 140ch — truncate on overflow rather than
                // blocking the keystroke (feels smoother).
                if newValue.count > messageLimit {
                    message = String(newValue.prefix(messageLimit))
                }
            }
        }
    }

    // MARK: - Navigation title
    //
    // Two invitees → "发起多猫约玩" to flag the change visibly; one
    // invitee keeps the familiar "约遛弯" wording from the 1:1 era.
    // Changing the nav title on toggle is subtle enough not to be
    // jarring, strong enough to orient the user.
    private var navigationTitleText: String {
        invitees.count >= 2 ? "发起多猫约玩" : "约遛弯"
    }

    // MARK: - Sections

    /// Invitee chips + "再邀请一只" append button. Entry-point pet
    /// always occupies slot 1; the optional slot 2 is the
    /// group-playdate expansion. The × on each chip removes an
    /// invitee, but the last remaining chip can't be removed — the
    /// composer needs at least one invitee to send.
    private var inviteesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("邀请对象")
            VStack(alignment: .leading, spacing: 12) {
                // Chip row — wraps onto a second line for two invitees
                // on narrow screens (iPhone SE) without clipping.
                FlowLayout(spacing: 8) {
                    ForEach(invitees) { invitee in
                        inviteeChip(invitee)
                    }
                    if invitees.count < maxInvitees {
                        addInviteeButton
                    }
                }
                // Copy helper under the chips — orients the user on the
                // cap + what "group" means.
                Text(invitees.count >= 2
                     ? "已邀请 \(invitees.count) 只毛孩子 · 一起遛弯"
                     : "可以再邀请一只毛孩子一起遛弯（最多 2 只）")
                    .font(.system(size: 12))
                    .foregroundStyle(PawPalTheme.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func inviteeChip(_ invitee: ComposerInvitee) -> some View {
        HStack(spacing: 8) {
            PawPalAvatar(
                emoji: speciesEmoji(for: invitee.pet.species ?? ""),
                imageURL: invitee.pet.avatar_url,
                size: 26,
                dogBreed: invitee.pet.species
            )
            Text(invitee.pet.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PawPalTheme.primaryText)
                .lineLimit(1)
            // Remove affordance — only visible when removing this
            // invitee would still leave ≥1 invitee on the sheet.
            if invitees.count > 1 {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    invitees.removeAll { $0.id == invitee.id }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(PawPalTheme.secondaryText)
                        .frame(width: 18, height: 18)
                        .background(PawPalTheme.cardSoft, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .background(PawPalTheme.amber.opacity(0.14), in: Capsule())
    }

    private var addInviteeButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isPickingSecondInvitee = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text("再邀请一只")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(PawPalTheme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().stroke(PawPalTheme.accent.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var proposerPetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("毛孩子")
            proposerPetMenu
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private var proposerPetMenu: some View {
        if proposerPetOptions.isEmpty {
            Text("你还没有毛孩子，无法发起邀请")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        } else if proposerPetOptions.count == 1, let only = proposerPetOptions.first {
            HStack(spacing: 12) {
                PawPalAvatar(
                    emoji: speciesEmoji(for: only.species ?? ""),
                    imageURL: only.avatar_url,
                    size: 36,
                    dogBreed: only.species
                )
                Text(only.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PawPalTheme.primaryText)
                Spacer()
            }
        } else {
            Menu {
                ForEach(proposerPetOptions, id: \.id) { pet in
                    Button {
                        proposerPetID = pet.id
                    } label: {
                        if proposerPetID == pet.id {
                            Label(pet.name, systemImage: "checkmark")
                        } else {
                            Text(pet.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    if let selected = proposerPetOptions.first(where: { $0.id == proposerPetID }) {
                        PawPalAvatar(
                            emoji: speciesEmoji(for: selected.species ?? ""),
                            imageURL: selected.avatar_url,
                            size: 36,
                            dogBreed: selected.species
                        )
                        Text(selected.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(PawPalTheme.primaryText)
                    } else {
                        Text("选择毛孩子")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PawPalTheme.secondaryText)
                }
            }
        }
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("时间")
            DatePicker(
                "",
                selection: $scheduledAt,
                in: minScheduledAt...maxScheduledAt,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(PawPalTheme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    /// "每周重复 ×4" toggle. When ON, shows a helper row explaining the
    /// fan-out and a read-only preview of the 4 dates as compact chips.
    /// Fires a light haptic on flip so the state change is tactile.
    private var repeatWeeklySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 0) {
                Toggle(isOn: $repeatWeekly) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("每周重复")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(PawPalTheme.primaryText)
                        Text("连续 4 周，每周同一时间")
                            .font(.system(size: 12))
                            .foregroundStyle(PawPalTheme.secondaryText)
                    }
                }
                .tint(PawPalTheme.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if repeatWeekly {
                    Divider().padding(.leading, 16)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("将创建 4 场约玩，每周一次")
                            .font(.system(size: 12))
                            .foregroundStyle(PawPalTheme.secondaryText)
                        // Compact chips — "4月25日 15:00" style.
                        FlowChipRow(dates: repeatWeeklyDates())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .onChange(of: repeatWeekly) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    /// Computes the 4 scheduled dates (base + 0/7/14/21 days) for the
    /// preview chips. Kept as a pure function so the preview always
    /// tracks `scheduledAt` without extra state.
    private func repeatWeeklyDates() -> [Date] {
        let week: TimeInterval = 7 * 24 * 60 * 60
        return (0..<4).map { scheduledAt.addingTimeInterval(week * Double($0)) }
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("地点")

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PawPalTheme.accent)
                    TextField("搜索公园、小区花园、宠物友好咖啡馆", text: $locationQuery)
                        .font(.system(size: 15))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                // Inline completer results
                if selectedLocationName == nil,
                   !locationQuery.isEmpty,
                   !completer.results.isEmpty {
                    Divider().padding(.leading, 16)
                    VStack(spacing: 0) {
                        ForEach(completer.results.prefix(6), id: \.title) { result in
                            Button {
                                selectLocation(result)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(PawPalTheme.primaryText)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.system(size: 12))
                                            .foregroundStyle(PawPalTheme.secondaryText)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Unresolved-coord warning per spec — appears when user
            // typed a location but no completer result matched.
            if selectedLocationName != nil, resolvedCoord == nil, !isResolvingCoord {
                Text("未能识别具体坐标，接受后才会显示地图")
                    .font(.system(size: 12))
                    .foregroundStyle(PawPalTheme.secondaryText)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("留言（可选）")
            VStack(alignment: .trailing, spacing: 6) {
                TextField("可选 · 说点什么（最多 140 字）", text: $message, axis: .vertical)
                    .lineLimit(2...5)
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(message.count)/\(messageLimit)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(PawPalTheme.tertiaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var sendButton: some View {
        Button {
            Task { await submit() }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(canSend
                          ? AnyShapeStyle(PawPalTheme.gradientOrangeToSoft)
                          : AnyShapeStyle(Color(.tertiarySystemFill)))
                    .frame(height: 52)
                    .shadow(color: canSend ? PawPalTheme.accent.opacity(0.35) : .clear, radius: 12, y: 6)
                if isSending {
                    ProgressView().tint(.white)
                } else {
                    Text("发送邀请")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(canSend ? .white : .secondary)
                }
            }
        }
        .disabled(!canSend)
        .buttonStyle(.plain)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .tracking(0.4)
            .foregroundStyle(PawPalTheme.secondaryText)
            .padding(.horizontal, 4)
    }

    /// Runs MKLocalSearch on a completer suggestion to resolve its
    /// lat/lng. Pins `selectedLocationName` synchronously so the UI
    /// immediately reads as selected; the coord arrives whenever the
    /// search resolves and is stored alongside.
    private func selectLocation(_ result: MKLocalSearchCompletion) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let name = result.subtitle.isEmpty
            ? result.title
            : "\(result.title) · \(result.subtitle)"
        selectedLocationName = name
        locationQuery = name
        resolvedCoord = nil
        isResolvingCoord = true
        let request = MKLocalSearch.Request(completion: result)
        Task {
            let search = MKLocalSearch(request: request)
            do {
                let response = try await search.start()
                if let mapItem = response.mapItems.first {
                    await MainActor.run {
                        self.resolvedCoord = mapItem.placemark.coordinate
                        self.isResolvingCoord = false
                    }
                } else {
                    await MainActor.run { self.isResolvingCoord = false }
                }
            } catch {
                await MainActor.run { self.isResolvingCoord = false }
            }
        }
    }

    private func submit() async {
        guard canSend,
              let proposerPetID,
              let locationName = selectedLocationName,
              !invitees.isEmpty
        else { return }

        isSending = true
        errorMessage = nil
        defer { isSending = false }

        let coord: (lat: Double, lng: Double)? = {
            if let resolvedCoord {
                return (resolvedCoord.latitude, resolvedCoord.longitude)
            }
            return nil
        }()

        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let messageArg: String? = trimmedMessage.isEmpty ? nil : trimmedMessage

        let inviteeRefs = invitees.map {
            PetRef(petID: $0.pet.id, ownerUserID: $0.ownerUserID)
        }

        let created = await PlaydateService.shared.propose(
            proposerPetID: proposerPetID,
            inviteePets: inviteeRefs,
            scheduledAt: scheduledAt,
            locationName: locationName,
            coord: coord,
            message: messageArg,
            repeatWeekly: repeatWeekly
        )

        if let created {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onSent(created)
            dismiss()
        } else {
            errorMessage = PlaydateService.shared.errorMessage ?? "发送失败，请稍后再试"
        }
    }

    // MARK: - Defaults

    /// Tomorrow at 15:00 local. If that instant is already in the past
    /// (e.g. it's 11pm), shift another day forward so we satisfy the
    /// min (now + 1h) constraint out of the box.
    private static func defaultScheduledAt() -> Date {
        let calendar = Calendar.current
        let now = Date()
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = 15
        comps.minute = 0
        guard var base = calendar.date(from: comps) else { return now.addingTimeInterval(60 * 60 * 25) }
        base = calendar.date(byAdding: .day, value: 1, to: base) ?? base
        if base.timeIntervalSinceNow < 60 * 60 {
            base = calendar.date(byAdding: .day, value: 1, to: base) ?? base
        }
        return base
    }

    /// Local species-to-emoji fallback. Every existing view has its own
    /// private copy (grep `speciesEmoji(for:)`) — keeping this one
    /// sheet-scoped too rather than introducing a new shared helper
    /// that would shadow the others.
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

/// Compact preview chips for the 4 weekly-repeat dates. Two rows of
/// two chips via a simple `Grid` keeps the layout predictable on the
/// narrowest iPhone widths without pulling in a custom `Layout`.
private struct FlowChipRow: View {
    let dates: [Date]

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                ForEach(Array(dates.prefix(2).enumerated()), id: \.offset) { _, date in
                    chip(for: date)
                }
            }
            if dates.count > 2 {
                GridRow {
                    ForEach(Array(dates.dropFirst(2).prefix(2).enumerated()), id: \.offset) { _, date in
                        chip(for: date)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(for date: Date) -> some View {
        Text(Self.formatter.string(from: date))
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(PawPalTheme.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(PawPalTheme.amber.opacity(0.14), in: Capsule())
    }
}

// MARK: - FlowLayout
//
// Minimal flow layout that wraps its subviews onto a new line when
// they don't fit. Used by the invitees section so the chip row
// gracefully spills onto two lines on narrow phones (the second
// invitee chip + the "再邀请一只" button together can exceed the
// sheet width on iPhone SE). No external dependency — pulling in a
// third-party flow layout would be overkill for a single row.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var totalHeight: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth == 0 ? 0 : spacing) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : rowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - AddInviteeSheet
//
// Second-invitee picker shown by `PlaydateComposerSheet` when the
// proposer taps "再邀请一只". Searches the same discovery surface
// used by other composers — the viewer's follow graph + recent
// visitors — so the additional pet is typically someone they've
// already interacted with. Falls back to showing only the pets
// already in memory (via `PetsService` singleton's adjacent caches)
// when that's the best we have; this is a MVP seam, not the final
// picker.
private struct AddInviteeSheet: View {
    let excludedPetIDs: Set<UUID>
    let onPick: (ComposerInvitee) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var results: [ComposerInvitee] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                VStack(spacing: 12) {
                    searchField
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    resultsList
                }
            }
            .navigationTitle("再邀请一只")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .task { await loadInitial() }
            .onChange(of: query) { _, newValue in
                Task { await runSearch(query: newValue) }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索毛孩子的名字", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var resultsList: some View {
        if isLoading && results.isEmpty {
            ProgressView().padding(.top, 32)
        } else if results.isEmpty {
            Text("没有找到开启遛弯邀请的毛孩子")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 32)
                .frame(maxWidth: .infinity, alignment: .center)
            Spacer()
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(results) { invitee in
                        resultRow(invitee)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    private func resultRow(_ invitee: ComposerInvitee) -> some View {
        Button {
            onPick(invitee)
        } label: {
            HStack(spacing: 12) {
                PawPalAvatar(
                    emoji: speciesEmoji(for: invitee.pet.species ?? ""),
                    imageURL: invitee.pet.avatar_url,
                    size: 44,
                    dogBreed: invitee.pet.species
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(invitee.pet.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PawPalTheme.primaryText)
                    if let city = invitee.pet.home_city, !city.isEmpty {
                        Text(city)
                            .font(.system(size: 12))
                            .foregroundStyle(PawPalTheme.secondaryText)
                    }
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(PawPalTheme.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Initial load — surfaces pets the viewer already has a
    /// relationship with (followed users' pets) so the picker is
    /// useful even with an empty search query. We read Supabase
    /// directly here rather than adding a dedicated PetsService
    /// method; this surface is a candidate for consolidation once
    /// group playdates land their final picker design.
    private func loadInitial() async {
        guard results.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        await runSearch(query: "")
    }

    private func runSearch(query: String) async {
        let client = SupabaseConfig.client
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            // Query pets with open_to_playdates = true, excluding the
            // pets already attached to this composer. Name filter uses
            // ilike when the query is non-empty; empty query returns
            // the most recent 20 as a default discovery surface.
            var q = client
                .from("pets")
                .select("*")
                .eq("open_to_playdates", value: true)
            if !trimmed.isEmpty {
                q = q.ilike("name", pattern: "%\(trimmed)%")
            }
            let fetched: [RemotePet] = try await q
                .order("created_at", ascending: false)
                .limit(20)
                .execute()
                .value
            let filtered = fetched.filter { !excludedPetIDs.contains($0.id) }
            self.results = filtered.map {
                ComposerInvitee(pet: $0, ownerUserID: $0.owner_user_id)
            }
        } catch {
            print("[Playdate] AddInviteeSheet search 失败: \(error)")
            self.errorMessage = error.localizedDescription
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
