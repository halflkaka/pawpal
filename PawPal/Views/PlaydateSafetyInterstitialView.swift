import SwiftUI

/// First-time safety primer shown before the playdate composer. A user
/// who taps the 约遛弯 pill before they've seen the three-bullet primer
/// gets this sheet first — on "知道了" we flip the
/// `pawpal.playdate.safety.seen` UserDefaults flag so subsequent
/// proposals open the composer directly.
///
/// Copy and icons come from §5.7 and §7 of
/// `docs/sessions/2026-04-18-pm-playdates-mvp-execution.md`.
struct PlaydateSafetyInterstitialView: View {
    let onContinue: () -> Void
    @Environment(\.dismiss) private var dismiss

    /// Bullet rows — SF Symbol + title + subtitle. Keeping them in a
    /// const list avoids repeating the HStack layout for each row.
    private let bullets: [(icon: String, title: String, subtitle: String)] = [
        ("person.2.fill", "公共场所见面", "选个开放的场地，彼此都更安心"),
        ("syringe.fill", "检查疫苗状态", "确认双方毛孩子的疫苗都是最新的"),
        ("drop.fill", "带够水", "跑一会就会渴，自带水和小食最靠谱")
    ]

    var body: some View {
        ZStack {
            PawPalBackground()

            VStack(spacing: 0) {
                // Drag handle hint so sheet feels like a dismissible card
                Capsule()
                    .fill(PawPalTheme.hairline)
                    .frame(width: 40, height: 4)
                    .padding(.top, 8)
                    .padding(.bottom, 18)

                // Title
                VStack(spacing: 6) {
                    Text("🐾")
                        .font(.system(size: 36))
                    Text("遛弯前需要知道的事")
                        .font(PawPalFont.rounded(size: 22, weight: .bold))
                        .foregroundStyle(PawPalTheme.primaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

                // Bullet list
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(bullets, id: \.icon) { bullet in
                        bulletRow(icon: bullet.icon,
                                  title: bullet.title,
                                  subtitle: bullet.subtitle)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: PawPalRadius.xxl, style: .continuous)
                        .fill(PawPalTheme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PawPalRadius.xxl, style: .continuous)
                        .stroke(PawPalTheme.hairline, lineWidth: 0.5)
                )
                .shadow(color: PawPalTheme.softShadow, radius: 12, y: 2)
                .padding(.horizontal, 18)

                Spacer(minLength: 24)

                // CTA
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onContinue()
                    dismiss()
                } label: {
                    Text("知道了")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            PawPalTheme.gradientOrangeToSoft,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .shadow(color: PawPalTheme.accent.opacity(0.35), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private func bulletRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(PawPalTheme.accentTint)
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(PawPalTheme.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(PawPalTheme.primaryText)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(PawPalTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
