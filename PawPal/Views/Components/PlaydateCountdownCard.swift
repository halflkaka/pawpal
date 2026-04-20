import SwiftUI

/// Accent-tinted pinned card rendered in FeedView for any accepted
/// playdate scheduled within the next 48h. Tapping it navigates to
/// `PlaydateDetailView`.
///
/// Layout slots:
///   * left — stacked pet avatars (36pt, 8pt offset)
///   * middle — eyebrow ("即将遛弯") + title + secondary
///   * right — countdown chip
///
/// Copy rules per §5.4 / §7 of
/// `docs/sessions/2026-04-18-pm-playdates-mvp-execution.md`.
struct PlaydateCountdownCard: View {
    let playdate: RemotePlaydate
    let proposerPet: RemotePet?
    let inviteePet: RemotePet?
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }) {
            HStack(alignment: .center, spacing: 14) {
                stackedAvatars
                middleStack
                Spacer(minLength: 4)
                countdownChip
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(PawPalTheme.accentTint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(PawPalTheme.accentGlow.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: PawPalTheme.softShadow, radius: 10, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subviews

    private var stackedAvatars: some View {
        HStack(spacing: -8) {
            avatar(for: proposerPet)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .zIndex(1)
            avatar(for: inviteePet)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
        }
    }

    @ViewBuilder
    private func avatar(for pet: RemotePet?) -> some View {
        if let pet {
            PawPalAvatar(
                emoji: speciesEmoji(for: pet.species ?? ""),
                imageURL: pet.avatar_url,
                size: 36,
                dogBreed: pet.species
            )
        } else {
            Circle()
                .fill(Color.white)
                .frame(width: 36, height: 36)
                .overlay(Text("🐾").font(.system(size: 16)))
        }
    }

    private var middleStack: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("即将遛弯")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(PawPalTheme.accent)

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
    }

    private var countdownChip: some View {
        Text(countdownText)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(PawPalTheme.accent, in: Capsule())
    }

    // MARK: - Copy

    private var titleText: String {
        let proposerName = proposerPet?.name ?? "毛孩子"
        let inviteeName  = inviteePet?.name  ?? "毛孩子"
        return "\(weekdayTime) · \(proposerName) 约了 \(inviteeName) 遛弯"
    }

    private var weekdayTime: String {
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "zh_CN")
        weekdayFormatter.dateFormat = "EEEE"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_CN")
        timeFormatter.dateFormat = "HH:mm"
        return "\(weekdayFormatter.string(from: playdate.scheduled_at)) \(timeFormatter.string(from: playdate.scheduled_at))"
    }

    private var secondaryText: String {
        playdate.location_name
    }

    private var countdownText: String {
        let now = Date()
        let delta = playdate.scheduled_at.timeIntervalSince(now)
        if delta <= 0 {
            // Between T-0 and T+2h → 正在遛弯中
            if abs(delta) <= 2 * 60 * 60 {
                return "正在遛弯中"
            }
            return "已结束"
        }
        let days = Int(delta / 86400)
        if days >= 1 {
            return "还有 \(days) 天"
        }
        let hours = Int(delta / 3600)
        if hours >= 1 {
            return "还有 \(hours) 小时"
        }
        let minutes = max(1, Int(delta / 60))
        return "还有 \(minutes) 分钟"
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
