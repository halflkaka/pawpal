import SwiftUI

// MARK: - PawPal Theme
//
// New design tokens (April 2026 refactor) calibrated against the design
// prototype. Names from the previous palette are kept as aliases so existing
// views keep compiling while we migrate visuals over.
//
// Tokens are loosely grouped as:
//   * Surfaces  — background, paper, card, subtle (warm cream + light wash)
//   * Accent    — accent (orange), warmth (peach), and supporting hues
//   * Text      — ink (primary), muted (secondary), faint (tertiary)
//   * Stats     — hunger (amber), energy (mint), online (bright green)
//
// Hex values map to the prototype's CSS:
//   accent  #FF7A52   bg     #FAF6F0   subtle  #F4F0ED   subtle2 #FAF7F4
//   ink     #1A1614   muted  #8B7C6D   hunger  #F6A23C   energy  #4BB58A

struct PawPalTheme {

    // MARK: Surfaces (cream paper)

    /// Page background. Warm cream — matches the prototype's `#FAF6F0`.
    static let background = Color(red: 0.980, green: 0.965, blue: 0.941)

    /// Slightly warmer cream used to layer radial highlights on the background.
    static let backgroundAccent = Color(red: 0.961, green: 0.929, blue: 0.882)

    /// Floating surfaces (cards, sheets). Pure white reads cleanest on cream.
    static let surface = Color.white

    /// Primary card colour. White — keeps polaroid posts crisp.
    static let card = Color.white

    /// Soft cream used for grouped rows, search bars, inactive chips, etc.
    /// Maps to prototype `#F4F0ED`.
    static let cardSoft = Color(red: 0.957, green: 0.941, blue: 0.929)

    /// Even softer warm wash used as a secondary surface on the profile,
    /// composer fields, etc. Maps to prototype `#FAF7F4`.
    static let subtleSurface = Color(red: 0.980, green: 0.969, blue: 0.957)

    // MARK: Accent (warm orange family)

    /// Brand accent. Maps to prototype `#FF7A52`.
    static let accent = Color(red: 1.00, green: 0.478, blue: 0.322)

    /// Slightly muted accent for hovers / pressed states. `#E88B5C`.
    static let accentSoft = Color(red: 0.910, green: 0.545, blue: 0.361)

    /// Very soft accent halo for backgrounds. ~`#FFD7C2`.
    static let accentGlow = Color(red: 1.00, green: 0.843, blue: 0.761)

    /// Pale accent used for highlighted chips ("end of today's walk" footer).
    static let accentTint = Color(red: 1.00, green: 0.945, blue: 0.910)

    // Backwards-compatible aliases for old PawPalTheme.orange/orangeSoft/orangeGlow
    static let orange = accent
    static let orangeSoft = accentSoft
    static let orangeGlow = accentGlow

    // MARK: Supporting hues (used for tags, accents, mood chips)

    /// Mint green for energy / positive stats. `#4BB58A`.
    static let mint = Color(red: 0.294, green: 0.710, blue: 0.541)

    /// Amber for hunger stats and warm accents. `#F6A23C`.
    static let amber = Color(red: 0.965, green: 0.635, blue: 0.235)

    /// Bright "online" green dot. `#4ADE80`.
    static let online = Color(red: 0.290, green: 0.871, blue: 0.502)

    /// Cool blue used in mood/tag accents. `#5B8FD9`.
    static let cool = Color(red: 0.357, green: 0.561, blue: 0.851)

    /// Warm berry tone for the friend/like badge. `#B77CD9`.
    static let berry = Color(red: 0.718, green: 0.486, blue: 0.851)

    // Backwards-compatible aliases
    static let pink = Color(red: 1.00, green: 0.78, blue: 0.81)   // pet bg variant
    static let yellow = amber
    static let green = mint
    static let red = Color(red: 0.93, green: 0.31, blue: 0.31)

    // MARK: Text

    /// Primary ink. Near-black warm brown — `#1A1614`.
    static let primaryText = Color(red: 0.102, green: 0.086, blue: 0.078)

    /// Secondary muted text — `#8B7C6D`.
    static let secondaryText = Color(red: 0.545, green: 0.486, blue: 0.427)

    /// Tertiary text (timestamps, faint hints).
    static let tertiaryText = Color(red: 0.667, green: 0.612, blue: 0.557)

    // MARK: Borders & shadows

    /// Hairline border — `rgba(26,22,20,0.08)`.
    static let hairline = Color(red: 0.102, green: 0.086, blue: 0.078).opacity(0.08)

    /// Card shadow — keeps cards floating without a heavy drop.
    static let shadow = Color(red: 0.102, green: 0.086, blue: 0.078).opacity(0.10)

    /// Even softer shadow for chips / pills.
    static let softShadow = Color(red: 0.102, green: 0.086, blue: 0.078).opacity(0.06)

    // MARK: Gradients

    /// Brand gradient used for primary CTA buttons.
    static let gradientOrangeToSoft = LinearGradient(
        colors: [PawPalTheme.accent, PawPalTheme.accentSoft],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Vignette overlay for hero photos.
    static let gradientImageOverlay = LinearGradient(
        colors: [Color.black.opacity(0.0), Color.black.opacity(0.28)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Conic gradient used for story rings.
    static let storyRingGradient = AngularGradient(
        gradient: Gradient(colors: [
            PawPalTheme.accent,
            PawPalTheme.amber,
            PawPalTheme.berry,
            PawPalTheme.accent
        ]),
        center: .center
    )

    /// Inactive divider tone used by the old design system.
    static let accentLineColor = PawPalTheme.hairline
}

// MARK: - Radii / Spacing tokens

enum PawPalRadius {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 18
    static let xl: CGFloat = 22
    static let xxl: CGFloat = 26
    static let pill: CGFloat = 999
}

enum PawPalSpacing {
    static let hairline: CGFloat = 0.5
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
}

// MARK: - Typography helpers

enum PawPalFont {
    /// Brand serif — falls back to system serif (New York) since we can't
    /// load Fraunces directly on iOS without bundling the otf.
    static func serif(size: CGFloat, weight: Font.Weight = .semibold, italic: Bool = false) -> Font {
        var font = Font.system(size: size, weight: weight, design: .serif)
        if italic { font = font.italic() }
        return font
    }

    /// Standard rounded display font used for stat values, levels, etc.
    static func rounded(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        Font.system(size: size, weight: weight, design: .rounded)
    }

    /// Default UI text — system "SF Pro Text" feel.
    static func ui(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: .default)
    }
}

// MARK: - Background

/// Warm cream background with two soft radial highlights — mirrors the
/// prototype's `radial-gradient(... at top left, ... at bottom right)` body.
struct PawPalBackground: View {
    var body: some View {
        ZStack {
            PawPalTheme.background
                .ignoresSafeArea()
            RadialGradient(
                colors: [PawPalTheme.accentGlow.opacity(0.30), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [PawPalTheme.backgroundAccent.opacity(0.55), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Card modifier

struct PawPalCardModifier: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat
    var stroke: Bool

    init(padding: CGFloat = 16, radius: CGFloat = PawPalRadius.xxl, stroke: Bool = true) {
        self.padding = padding
        self.radius = radius
        self.stroke = stroke
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(PawPalTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(stroke ? PawPalTheme.hairline : Color.clear, lineWidth: 0.5)
            )
            .shadow(color: PawPalTheme.softShadow, radius: 14, y: 2)
    }
}

extension View {
    func pawPalCard(
        padding: CGFloat = 16,
        radius: CGFloat = PawPalRadius.xxl,
        stroke: Bool = true
    ) -> some View {
        modifier(PawPalCardModifier(padding: padding, radius: radius, stroke: stroke))
    }

    func bottomAccentLine() -> some View {
        VStack(spacing: 0) {
            self
            Rectangle().fill(PawPalTheme.hairline).frame(height: 0.5)
        }
    }

    /// Polaroid card tilt used by feed posts — alternating subtle rotation.
    func pawPalPolaroidTilt(index: Int) -> some View {
        let tilt: Double = (index % 2 == 0) ? -0.6 : 0.5
        return self.rotationEffect(.degrees(tilt))
    }

    /// Iridescent/glass pill background for sticky headers and overlays.
    func pawPalGlass(radius: CGFloat = PawPalRadius.pill) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.6), lineWidth: 0.5)
            )
            .shadow(color: PawPalTheme.softShadow, radius: 6, y: 1)
    }
}

// MARK: - Section title

struct PawPalSectionTitle: View {
    let title: String
    let emoji: String?
    var serif: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if let emoji {
                Text(emoji)
            }
            Text(title)
                .font(serif
                      ? PawPalFont.serif(size: 22, weight: .semibold)
                      : PawPalFont.rounded(size: 22, weight: .bold))
                .foregroundStyle(PawPalTheme.primaryText)
            Spacer()
        }
    }
}

// MARK: - Section eyebrow (small caps muted label)

struct PawPalEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(PawPalFont.ui(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(PawPalTheme.secondaryText)
    }
}

// MARK: - Pills / chips

struct PawPalPill: View {
    let text: String
    let systemImage: String?
    var tint: Color = PawPalTheme.accent
    var filled: Bool = false

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
        .foregroundStyle(filled ? Color.white : tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(filled ? tint : tint.opacity(0.12), in: Capsule())
    }
}

/// Subtle action chip used in feed footers, profile actions, etc.
/// Cream-tinted background, dark ink text, optional system icon.
struct PawPalActionChip: View {
    let text: String?
    let systemImage: String?
    var tint: Color = PawPalTheme.primaryText
    var background: Color = PawPalTheme.cardSoft

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
            }
            if let text {
                Text(text)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(background, in: Capsule())
    }
}

// MARK: - Stat bar (mood / hunger / energy)

struct PawPalStatBar: View {
    let label: String
    let value: Int                 // 0...100
    var color: Color = PawPalTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(PawPalFont.ui(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(PawPalTheme.secondaryText)
                Spacer()
                Text("\(max(0, min(100, value)))")
                    .font(PawPalFont.rounded(size: 11, weight: .bold))
                    .foregroundStyle(PawPalTheme.primaryText)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(PawPalTheme.cardSoft)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(max(0, min(100, value))) / 100.0)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Avatar (photo → SVG dog → emoji fallback chain)

/// `PawPalAvatar` keeps its existing call-sites working but now prefers the
/// stylised `DogAvatar` illustration whenever no photo URL is available.
struct PawPalAvatar: View {
    let emoji: String
    var imageURL: String? = nil
    var size: CGFloat = 52
    var background: Color = PawPalTheme.cardSoft
    var ringColor: Color? = nil
    /// Optional dog breed hint used to pick the illustrated avatar variant.
    /// Pass any Chinese / English breed string — `DogAvatar` figures it out.
    var dogBreed: String? = nil
    /// If true and no photo URL is set, the emoji is used directly without
    /// trying the illustrated dog avatar. Useful for cats/rabbits/etc.
    var preferEmoji: Bool = false

    var body: some View {
        ZStack {
            Circle().fill(background)
            content
        }
        .frame(width: size, height: size)
        .overlay {
            if let ringColor {
                Circle()
                    .stroke(ringColor, lineWidth: max(2, size * 0.06))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let urlString = imageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    // Real load error — show the illustrated fallback.
                    fallback
                case .empty:
                    // Still loading. Previously this branch also rendered
                    // `fallback`, which meant every re-appearance of the
                    // avatar (scrolling the feed, navigating back) would
                    // flash the illustrated placeholder for a few hundred
                    // ms before the photo arrived — reading as "this pet
                    // has no avatar" even when one existed. Now we keep
                    // the circle filled with the background tint during
                    // load, so the avatar appears to pop in rather than
                    // swap. URLCache (configured in PawPalApp) keeps
                    // repeat loads near-instant so this phase is brief.
                    Color.clear
                @unknown default:
                    fallback
                }
            }
            .clipShape(Circle())
        } else {
            fallback
        }
    }

    @ViewBuilder
    private var fallback: some View {
        if !preferEmoji {
            DogAvatar(
                variant: DogAvatar.Variant.from(breed: dogBreed),
                size: size,
                background: .clear
            )
        } else {
            Text(emoji).font(.system(size: size * 0.46))
        }
    }
}

// MARK: - Bottom bar background (tab bar)

struct PawPalBottomBarBackground: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(PawPalTheme.hairline)
                    .frame(height: 0.5)
            }
            .ignoresSafeArea(edges: .bottom)
    }
}
