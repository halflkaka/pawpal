import SwiftUI

struct PawPalTheme {
    static let background = Color(red: 1.00, green: 0.98, blue: 0.96)
    static let backgroundAccent = Color(red: 1.00, green: 0.94, blue: 0.89)
    static let surface = Color.white.opacity(0.92)
    static let card = Color.white
    static let cardSoft = Color(red: 1.00, green: 0.95, blue: 0.91)
    static let primaryText = Color(red: 0.16, green: 0.10, blue: 0.04)
    static let secondaryText = Color(red: 0.48, green: 0.31, blue: 0.18)
    static let tertiaryText = Color(red: 0.72, green: 0.56, blue: 0.50)
    static let orange = Color(red: 1.00, green: 0.42, blue: 0.21)
    static let orangeSoft = Color(red: 1.00, green: 0.60, blue: 0.31)
    static let orangeGlow = Color(red: 1.00, green: 0.82, blue: 0.66)
    static let pink = Color(red: 1.00, green: 0.75, blue: 0.84)
    static let yellow = Color(red: 1.00, green: 0.84, blue: 0.40)
    static let green = Color(red: 0.66, green: 0.85, blue: 0.66)
    static let red = Color(red: 1.00, green: 0.28, blue: 0.34)
    static let shadow = Color(red: 0.48, green: 0.31, blue: 0.18).opacity(0.10)
    static let softShadow = Color(red: 0.48, green: 0.31, blue: 0.18).opacity(0.06)
}

struct PawPalBackground: View {
    var body: some View {
        LinearGradient(
            colors: [PawPalTheme.background, PawPalTheme.backgroundAccent],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(
            RadialGradient(
                colors: [PawPalTheme.orangeGlow.opacity(0.22), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 360
            )
        )
        .ignoresSafeArea()
    }
}

struct PawPalCardModifier: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(PawPalTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: PawPalTheme.shadow, radius: 16, y: 6)
    }
}

extension View {
    func pawPalCard(padding: CGFloat = 16) -> some View {
        modifier(PawPalCardModifier(padding: padding))
    }
}

struct PawPalSectionTitle: View {
    let title: String
    let emoji: String?

    var body: some View {
        HStack(spacing: 8) {
            if let emoji {
                Text(emoji)
            }
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
            Spacer()
        }
    }
}

struct PawPalPill: View {
    let text: String
    let systemImage: String?
    var tint: Color = PawPalTheme.orange

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

struct PawPalAvatar: View {
    let emoji: String
    var size: CGFloat = 52
    var background: Color = PawPalTheme.cardSoft
    var ringColor: Color? = nil

    var body: some View {
        ZStack {
            Circle()
                .fill(background)
            Text(emoji)
                .font(.system(size: size * 0.46))
        }
        .frame(width: size, height: size)
        .overlay {
            if let ringColor {
                Circle()
                    .stroke(ringColor, lineWidth: max(2, size * 0.06))
            }
        }
    }
}

struct PawPalBottomBarBackground: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Divider()
                    .overlay(Color.black.opacity(0.03))
            }
            .ignoresSafeArea(edges: .bottom)
    }
}
