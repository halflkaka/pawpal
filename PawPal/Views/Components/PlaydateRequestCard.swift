import SwiftUI

/// Soft-yellow pinned card surfaced in FeedView for any `proposed`
/// playdate where the viewer is the invitee. Accept/Decline buttons
/// call `PlaydateService` inline; tapping the card body (anywhere that
/// isn't a button) navigates to `PlaydateDetailView`.
///
/// Copy per §5.5 / §7 of
/// `docs/sessions/2026-04-18-pm-playdates-mvp-execution.md`.
struct PlaydateRequestCard: View {
    let playdate: RemotePlaydate
    let proposerPet: RemotePet?
    let inviteePet: RemotePet?
    let onTap: () -> Void

    @State private var isMutating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
            actionsRow
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(PawPalTheme.amber.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PawPalTheme.amber.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: PawPalTheme.softShadow, radius: 10, y: 2)
        // Body tap — excluded regions (the action buttons) intercept
        // first because of SwiftUI's event routing, so only the
        // "background" portion of the card routes to onTap.
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            avatar(for: proposerPet, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(titleText)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PawPalTheme.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(secondaryText)
                    .font(.system(size: 12))
                    .foregroundStyle(PawPalTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 10) {
            Button {
                Task { await decline() }
            } label: {
                Text("拒绝")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PawPalTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Color.white.opacity(0.8), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isMutating)

            Button {
                Task { await accept() }
            } label: {
                Text("接受")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(PawPalTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isMutating)
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

    // MARK: - Copy

    private var titleText: String {
        let proposerName = proposerPet?.name ?? "毛孩子"
        let inviteeName  = inviteePet?.name  ?? "毛孩子"
        return "\(proposerName) 想和 \(inviteeName) 遛弯"
    }

    private var secondaryText: String {
        "\(relativeTime) · 在 \(districtSlice(from: playdate.location_name))"
    }

    private var relativeTime: String {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: playdate.scheduled_at)
        let segment: String
        switch hour {
        case ..<12: segment = "早上"
        case 12..<18: segment = "下午"
        default: segment = "晚上"
        }
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "zh_CN")
        weekdayFormatter.dateFormat = "EEEE"
        return "\(weekdayFormatter.string(from: playdate.scheduled_at))\(segment)"
    }

    private func districtSlice(from raw: String) -> String {
        let tokens: [Character] = ["区", "县", "市"]
        guard let endIdx = raw.indices.reversed().first(where: { tokens.contains(raw[$0]) }) else {
            return "对方的附近"
        }
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

    // MARK: - Mutations

    private func accept() async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let ok = await PlaydateService.shared.accept(playdate.id)
        if !ok {
            errorMessage = PlaydateService.shared.errorMessage ?? "操作失败"
        }
    }

    private func decline() async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        let ok = await PlaydateService.shared.decline(playdate.id)
        if !ok {
            errorMessage = PlaydateService.shared.errorMessage ?? "操作失败"
        }
    }
}
