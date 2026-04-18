import SwiftUI
import UIKit

/// Curated SwiftUI illustrations of the featured pet on the profile page.
///
/// The art is entirely made of `Circle`, `Ellipse`, `RoundedRectangle` and
/// `Path`, so it scales crisply at any size and picks up the warm PawPal
/// palette automatically. Species-specific shapes are drawn on top of a
/// shared "blob" body to keep each character recognisable without bloating
/// the file with dozens of custom paths.
///
/// The view reacts to taps with a spring bounce + haptic, and briefly
/// flips the mood to `.excited` — giving the character a "tap me" feel
/// that matches the hand-drawn note in the profile mockup.
struct PetCharacterView: View {
    /// Matches the species strings the app stores in `RemotePet.species`
    /// ("Dog", "Cat", "Rabbit", "Bird", "Hamster", "Other").
    let species: String?

    /// The resting mood. Taps temporarily override this with `.excited`.
    let mood: PetCharacterMood

    /// Size of the square drawing canvas. Defaults to 200pt which matches
    /// the featured-pet slot on the profile page.
    var size: CGFloat = 200

    /// Optional callback fired after the tap animation so the parent can
    /// react (e.g. pulse a happiness meter).
    var onTap: (() -> Void)? = nil

    @State private var isPressed = false
    @State private var excitedFlashActive = false

    var body: some View {
        let currentMood = excitedFlashActive ? .excited : mood

        ZStack {
            // Soft backdrop glow so the character pops on the cream background.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            PawPalTheme.orangeGlow.opacity(0.55),
                            PawPalTheme.orangeGlow.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: size * 0.05,
                        endRadius: size * 0.55
                    )
                )

            character(for: species, mood: currentMood)
                .frame(width: size * 0.82, height: size * 0.82)

            if currentMood == .excited {
                sparkleOverlay
                    .transition(.scale.combined(with: .opacity))
            }
            if currentMood == .sleeping {
                sleepingOverlay
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isPressed)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: excitedFlashActive)
        .contentShape(Circle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onTap?()
            withAnimation { isPressed = true }
            withAnimation { excitedFlashActive = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation { isPressed = false }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                withAnimation { excitedFlashActive = false }
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("宠物角色")
    }

    // MARK: - Species routing

    @ViewBuilder
    private func character(for species: String?, mood: PetCharacterMood) -> some View {
        switch (species ?? "").lowercased() {
        case "cat":     CatCharacter(mood: mood)
        case "rabbit":  RabbitCharacter(mood: mood)
        case "bird":    BirdCharacter(mood: mood)
        case "hamster": HamsterCharacter(mood: mood)
        case "other":   BlobCharacter(mood: mood)
        default:        DogCharacter(mood: mood) // Dog is the most common pet; a sensible default
        }
    }

    // MARK: - Mood overlays

    private var sparkleOverlay: some View {
        ZStack {
            sparkle(at: CGPoint(x: size * 0.18, y: size * 0.22), scale: 0.55)
            sparkle(at: CGPoint(x: size * 0.82, y: size * 0.30), scale: 0.75)
            sparkle(at: CGPoint(x: size * 0.86, y: size * 0.70), scale: 0.50)
            sparkle(at: CGPoint(x: size * 0.14, y: size * 0.68), scale: 0.65)
        }
        .frame(width: size, height: size)
    }

    private func sparkle(at point: CGPoint, scale: CGFloat) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: 18 * scale, weight: .bold))
            .foregroundStyle(PawPalTheme.orange)
            .position(point)
    }

    private var sleepingOverlay: some View {
        VStack(alignment: .trailing, spacing: -4) {
            Text("Z")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(PawPalTheme.orange.opacity(0.7))
                .offset(x: -4, y: 0)
            Text("z")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(PawPalTheme.orange.opacity(0.55))
                .offset(x: -14, y: 0)
        }
        .frame(width: size, height: size, alignment: .topTrailing)
        .padding(.top, size * 0.12)
        .padding(.trailing, size * 0.12)
    }
}

// MARK: - Mood

enum PetCharacterMood: Equatable {
    case happy
    case excited
    case sleeping
    case energetic
    case chill

    /// Short Chinese label shown in the mood chip on the profile page.
    var chineseLabel: String {
        switch self {
        case .happy:     return "开心"
        case .excited:   return "兴奋"
        case .sleeping:  return "犯困"
        case .energetic: return "活力"
        case .chill:     return "慵懒"
        }
    }

    /// SF Symbol shown alongside the Chinese label.
    var systemImage: String {
        switch self {
        case .happy:     return "sparkles"
        case .excited:   return "party.popper.fill"
        case .sleeping:  return "moon.zzz.fill"
        case .energetic: return "bolt.fill"
        case .chill:     return "leaf.fill"
        }
    }

    /// Tint color used for the mood chip background.
    var tint: Color {
        switch self {
        case .happy:     return PawPalTheme.green
        case .excited:   return PawPalTheme.orange
        case .sleeping:  return PawPalTheme.tertiaryText
        case .energetic: return PawPalTheme.yellow
        case .chill:     return PawPalTheme.pink
        }
    }
}

// MARK: - Shared building blocks

/// A pair of eyes that adapts to the current mood. All characters share this
/// so expression changes feel consistent across species.
private struct CharacterEyes: View {
    let mood: PetCharacterMood
    var spacing: CGFloat = 26
    var size: CGFloat = 10
    var color: Color = .black

    var body: some View {
        HStack(spacing: spacing) {
            eye
            eye
        }
    }

    @ViewBuilder
    private var eye: some View {
        switch mood {
        case .sleeping:
            // Closed, curved eyelid
            Path { p in
                p.move(to: CGPoint(x: 0, y: size * 0.5))
                p.addQuadCurve(
                    to: CGPoint(x: size * 1.4, y: size * 0.5),
                    control: CGPoint(x: size * 0.7, y: -size * 0.2)
                )
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: size * 1.4, height: size)
        case .excited:
            // Big sparkly eyes
            ZStack {
                Circle().fill(color)
                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.45, height: size * 0.45)
                    .offset(x: size * 0.18, y: -size * 0.18)
            }
            .frame(width: size * 1.2, height: size * 1.2)
        default:
            // Friendly open eye
            ZStack {
                Circle().fill(color)
                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.35, height: size * 0.35)
                    .offset(x: size * 0.15, y: -size * 0.15)
            }
            .frame(width: size, height: size)
        }
    }
}

/// A small blush on each cheek — adds warmth.
private struct CharacterBlush: View {
    var spacing: CGFloat = 60
    var size: CGFloat = 10
    var body: some View {
        HStack(spacing: spacing) {
            Ellipse().fill(PawPalTheme.pink.opacity(0.65))
            Ellipse().fill(PawPalTheme.pink.opacity(0.65))
        }
        .frame(height: size * 0.7)
        .frame(maxWidth: .infinity)
    }
}

/// A mouth that reflects the mood (smile / small O / tiny sleep line).
private struct CharacterMouth: View {
    let mood: PetCharacterMood
    var width: CGFloat = 20
    var color: Color = .black

    var body: some View {
        switch mood {
        case .sleeping:
            Capsule()
                .fill(color)
                .frame(width: width * 0.4, height: 2)
        case .excited:
            // Open circle "o" — joyful
            Circle()
                .stroke(color, lineWidth: 2)
                .frame(width: width * 0.5, height: width * 0.5)
                .background(
                    Circle()
                        .fill(PawPalTheme.red.opacity(0.55))
                        .frame(width: width * 0.42, height: width * 0.42)
                )
        default:
            // Gentle upturned smile
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0))
                p.addQuadCurve(
                    to: CGPoint(x: width, y: 0),
                    control: CGPoint(x: width * 0.5, y: width * 0.5)
                )
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: width, height: width * 0.5)
        }
    }
}

// MARK: - Dog

private struct DogCharacter: View {
    let mood: PetCharacterMood

    private let body_ = PawPalTheme.orangeSoft
    private let head  = Color(red: 0.96, green: 0.75, blue: 0.55)
    private let ear   = Color(red: 0.76, green: 0.52, blue: 0.33)
    private let muzzle = Color(red: 1.00, green: 0.87, blue: 0.72)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Body (sitting blob)
                Ellipse()
                    .fill(body_)
                    .frame(width: w * 0.72, height: h * 0.30)
                    .position(x: w * 0.5, y: h * 0.86)
                    .shadow(color: PawPalTheme.shadow, radius: 6, y: 4)

                // Head
                Circle()
                    .fill(head)
                    .frame(width: w * 0.70, height: w * 0.70)
                    .position(x: w * 0.5, y: h * 0.50)
                    .shadow(color: PawPalTheme.shadow, radius: 6, y: 4)

                // Ears (floppy)
                Ellipse()
                    .fill(ear)
                    .frame(width: w * 0.22, height: h * 0.36)
                    .rotationEffect(.degrees(-15))
                    .position(x: w * 0.22, y: h * 0.44)
                Ellipse()
                    .fill(ear)
                    .frame(width: w * 0.22, height: h * 0.36)
                    .rotationEffect(.degrees(15))
                    .position(x: w * 0.78, y: h * 0.44)

                // Muzzle
                Ellipse()
                    .fill(muzzle)
                    .frame(width: w * 0.38, height: h * 0.22)
                    .position(x: w * 0.5, y: h * 0.64)

                // Nose
                Ellipse()
                    .fill(Color.black)
                    .frame(width: w * 0.10, height: h * 0.06)
                    .position(x: w * 0.5, y: h * 0.56)

                // Eyes
                CharacterEyes(mood: mood, spacing: w * 0.18, size: w * 0.07)
                    .position(x: w * 0.5, y: h * 0.46)

                // Mouth
                CharacterMouth(mood: mood, width: w * 0.16)
                    .position(x: w * 0.5, y: h * 0.68)

                // Cheeks
                HStack(spacing: w * 0.48) {
                    Ellipse().fill(PawPalTheme.pink.opacity(0.6))
                        .frame(width: w * 0.09, height: h * 0.04)
                    Ellipse().fill(PawPalTheme.pink.opacity(0.6))
                        .frame(width: w * 0.09, height: h * 0.04)
                }
                .position(x: w * 0.5, y: h * 0.56)

                // Collar
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(PawPalTheme.red)
                    .frame(width: w * 0.40, height: h * 0.05)
                    .position(x: w * 0.5, y: h * 0.76)
                Image(systemName: "heart.fill")
                    .font(.system(size: w * 0.05, weight: .bold))
                    .foregroundStyle(PawPalTheme.yellow)
                    .position(x: w * 0.5, y: h * 0.76)
            }
        }
    }
}

// MARK: - Cat

private struct CatCharacter: View {
    let mood: PetCharacterMood

    private let body_ = Color(red: 0.98, green: 0.78, blue: 0.55)
    private let ear   = Color(red: 0.82, green: 0.56, blue: 0.30)
    private let innerEar = PawPalTheme.pink

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Body
                Ellipse()
                    .fill(body_)
                    .frame(width: w * 0.68, height: h * 0.28)
                    .position(x: w * 0.5, y: h * 0.88)
                    .shadow(color: PawPalTheme.shadow, radius: 6, y: 4)

                // Head
                Circle()
                    .fill(body_)
                    .frame(width: w * 0.72, height: w * 0.72)
                    .position(x: w * 0.5, y: h * 0.52)
                    .shadow(color: PawPalTheme.shadow, radius: 6, y: 4)

                // Triangular ears
                triangleEar(color: ear, inner: innerEar)
                    .frame(width: w * 0.22, height: h * 0.22)
                    .rotationEffect(.degrees(-12))
                    .position(x: w * 0.30, y: h * 0.25)
                triangleEar(color: ear, inner: innerEar)
                    .frame(width: w * 0.22, height: h * 0.22)
                    .rotationEffect(.degrees(12))
                    .position(x: w * 0.70, y: h * 0.25)

                // Stripes on head (tabby)
                stripe.position(x: w * 0.35, y: h * 0.38)
                stripe.position(x: w * 0.50, y: h * 0.33)
                stripe.position(x: w * 0.65, y: h * 0.38)

                // Eyes
                CharacterEyes(mood: mood, spacing: w * 0.18, size: w * 0.08,
                              color: PawPalTheme.primaryText)
                    .position(x: w * 0.5, y: h * 0.50)

                // Nose
                nose.position(x: w * 0.5, y: h * 0.60)

                // Mouth
                CharacterMouth(mood: mood, width: w * 0.14)
                    .position(x: w * 0.5, y: h * 0.68)

                // Whiskers
                whiskers(on: w, h: h)

                // Cheeks
                HStack(spacing: w * 0.44) {
                    Ellipse().fill(PawPalTheme.pink.opacity(0.55))
                        .frame(width: w * 0.08, height: h * 0.035)
                    Ellipse().fill(PawPalTheme.pink.opacity(0.55))
                        .frame(width: w * 0.08, height: h * 0.035)
                }
                .position(x: w * 0.5, y: h * 0.60)
            }
        }
    }

    private var stripe: some View {
        Capsule()
            .fill(Color.black.opacity(0.12))
            .frame(width: 12, height: 3)
    }

    private var nose: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 14, y: 0))
            p.addLine(to: CGPoint(x: 7, y: 9))
            p.closeSubpath()
        }
        .fill(PawPalTheme.pink)
        .frame(width: 14, height: 9)
    }

    private func triangleEar(color: Color, inner: Color) -> some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 10, y: 0))
                p.addLine(to: CGPoint(x: 0, y: 40))
                p.addLine(to: CGPoint(x: 20, y: 40))
                p.closeSubpath()
            }
            .fill(color)
            Path { p in
                p.move(to: CGPoint(x: 10, y: 10))
                p.addLine(to: CGPoint(x: 5, y: 36))
                p.addLine(to: CGPoint(x: 15, y: 36))
                p.closeSubpath()
            }
            .fill(inner.opacity(0.8))
        }
        .frame(width: 20, height: 40)
    }

    private func whiskers(on w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            // Left
            Rectangle().fill(Color.black.opacity(0.35))
                .frame(width: w * 0.14, height: 1)
                .position(x: w * 0.26, y: h * 0.62)
            Rectangle().fill(Color.black.opacity(0.35))
                .frame(width: w * 0.14, height: 1)
                .position(x: w * 0.26, y: h * 0.66)
            // Right
            Rectangle().fill(Color.black.opacity(0.35))
                .frame(width: w * 0.14, height: 1)
                .position(x: w * 0.74, y: h * 0.62)
            Rectangle().fill(Color.black.opacity(0.35))
                .frame(width: w * 0.14, height: 1)
                .position(x: w * 0.74, y: h * 0.66)
        }
    }
}

// MARK: - Rabbit

private struct RabbitCharacter: View {
    let mood: PetCharacterMood

    private let body_  = Color(red: 1.00, green: 0.95, blue: 0.95)
    private let shade  = Color(red: 0.92, green: 0.82, blue: 0.80)
    private let ear    = Color(red: 0.98, green: 0.88, blue: 0.90)
    private let inner  = PawPalTheme.pink

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Long ears
                rabbitEar(color: ear, inner: inner)
                    .frame(width: w * 0.14, height: h * 0.42)
                    .rotationEffect(.degrees(-10))
                    .position(x: w * 0.42, y: h * 0.18)
                rabbitEar(color: ear, inner: inner)
                    .frame(width: w * 0.14, height: h * 0.42)
                    .rotationEffect(.degrees(10))
                    .position(x: w * 0.58, y: h * 0.18)

                // Body
                Ellipse()
                    .fill(body_)
                    .frame(width: w * 0.62, height: h * 0.28)
                    .position(x: w * 0.5, y: h * 0.90)
                    .shadow(color: PawPalTheme.shadow, radius: 6, y: 4)

                // Head
                Circle()
                    .fill(body_)
                    .frame(width: w * 0.66, height: w * 0.66)
                    .position(x: w * 0.5, y: h * 0.58)
                    .shadow(color: PawPalTheme.shadow, radius: 6, y: 4)

                // Subtle shade on bottom of head
                Ellipse()
                    .fill(shade.opacity(0.4))
                    .frame(width: w * 0.44, height: h * 0.15)
                    .position(x: w * 0.5, y: h * 0.72)

                // Eyes
                CharacterEyes(mood: mood, spacing: w * 0.17, size: w * 0.07)
                    .position(x: w * 0.5, y: h * 0.54)

                // Pink nose
                Ellipse()
                    .fill(PawPalTheme.pink)
                    .frame(width: w * 0.09, height: h * 0.05)
                    .position(x: w * 0.5, y: h * 0.66)

                // Buck teeth
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white)
                    .frame(width: w * 0.08, height: h * 0.08)
                    .overlay(
                        Rectangle().fill(Color.black.opacity(0.2))
                            .frame(width: 1)
                    )
                    .position(x: w * 0.5, y: h * 0.76)

                // Cheeks
                HStack(spacing: w * 0.42) {
                    Ellipse().fill(PawPalTheme.pink.opacity(0.55))
                        .frame(width: w * 0.09, height: h * 0.04)
                    Ellipse().fill(PawPalTheme.pink.opacity(0.55))
                        .frame(width: w * 0.09, height: h * 0.04)
                }
                .position(x: w * 0.5, y: h * 0.66)
            }
        }
    }

    private func rabbitEar(color: Color, inner: Color) -> some View {
        ZStack {
            Capsule().fill(color)
            Capsule().fill(inner.opacity(0.8))
                .scaleEffect(x: 0.5, y: 0.85)
        }
    }
}

// MARK: - Bird

private struct BirdCharacter: View {
    let mood: PetCharacterMood

    private let body_ = PawPalTheme.yellow
    private let wing  = Color(red: 0.95, green: 0.70, blue: 0.25)
    private let beak  = PawPalTheme.orange

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Round body
                Ellipse()
                    .fill(body_)
                    .frame(width: w * 0.74, height: h * 0.72)
                    .position(x: w * 0.5, y: h * 0.58)
                    .shadow(color: PawPalTheme.shadow, radius: 6, y: 4)

                // Wing
                Ellipse()
                    .fill(wing)
                    .frame(width: w * 0.32, height: h * 0.28)
                    .rotationEffect(.degrees(-18))
                    .position(x: w * 0.62, y: h * 0.64)

                // Beak
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0))
                    p.addLine(to: CGPoint(x: 18, y: 6))
                    p.addLine(to: CGPoint(x: 0, y: 12))
                    p.closeSubpath()
                }
                .fill(beak)
                .frame(width: 18, height: 12)
                .position(x: w * 0.30, y: h * 0.48)

                // Eye
                ZStack {
                    Circle().fill(Color.black)
                    Circle().fill(Color.white)
                        .frame(width: w * 0.02, height: w * 0.02)
                        .offset(x: w * 0.015, y: -w * 0.015)
                }
                .frame(width: w * 0.08, height: w * 0.08)
                .position(x: w * 0.42, y: h * 0.42)

                // Small feet
                feet.position(x: w * 0.5, y: h * 0.92)

                // Mood overlay (mouth line when sleeping)
                if mood == .sleeping {
                    Capsule().fill(Color.black.opacity(0.4))
                        .frame(width: w * 0.05, height: 2)
                        .position(x: w * 0.42, y: h * 0.42)
                }
            }
        }
    }

    private var feet: some View {
        HStack(spacing: 10) {
            Capsule().fill(PawPalTheme.orange).frame(width: 4, height: 14)
            Capsule().fill(PawPalTheme.orange).frame(width: 4, height: 14)
        }
    }
}

// MARK: - Hamster

private struct HamsterCharacter: View {
    let mood: PetCharacterMood

    private let body_ = Color(red: 0.98, green: 0.83, blue: 0.62)
    private let shade = Color(red: 1.00, green: 0.94, blue: 0.82)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Chubby body
                Ellipse()
                    .fill(body_)
                    .frame(width: w * 0.78, height: h * 0.82)
                    .position(x: w * 0.5, y: h * 0.54)
                    .shadow(color: PawPalTheme.shadow, radius: 6, y: 4)

                // Belly
                Ellipse()
                    .fill(shade)
                    .frame(width: w * 0.48, height: h * 0.44)
                    .position(x: w * 0.5, y: h * 0.66)

                // Tiny ears
                Circle().fill(body_)
                    .frame(width: w * 0.12, height: w * 0.12)
                    .position(x: w * 0.30, y: h * 0.22)
                Circle().fill(body_)
                    .frame(width: w * 0.12, height: w * 0.12)
                    .position(x: w * 0.70, y: h * 0.22)
                Circle().fill(PawPalTheme.pink.opacity(0.7))
                    .frame(width: w * 0.06, height: w * 0.06)
                    .position(x: w * 0.30, y: h * 0.22)
                Circle().fill(PawPalTheme.pink.opacity(0.7))
                    .frame(width: w * 0.06, height: w * 0.06)
                    .position(x: w * 0.70, y: h * 0.22)

                // Eyes
                CharacterEyes(mood: mood, spacing: w * 0.22, size: w * 0.06)
                    .position(x: w * 0.5, y: h * 0.44)

                // Nose
                Ellipse()
                    .fill(PawPalTheme.pink)
                    .frame(width: w * 0.06, height: h * 0.04)
                    .position(x: w * 0.5, y: h * 0.55)

                // Mouth
                CharacterMouth(mood: mood, width: w * 0.10)
                    .position(x: w * 0.5, y: h * 0.60)

                // Cheek pouches
                HStack(spacing: w * 0.52) {
                    Ellipse().fill(PawPalTheme.pink.opacity(0.55))
                        .frame(width: w * 0.10, height: h * 0.05)
                    Ellipse().fill(PawPalTheme.pink.opacity(0.55))
                        .frame(width: w * 0.10, height: h * 0.05)
                }
                .position(x: w * 0.5, y: h * 0.55)
            }
        }
    }
}

// MARK: - Other (friendly blob)

private struct BlobCharacter: View {
    let mood: PetCharacterMood

    private let body_ = Color(red: 0.78, green: 0.86, blue: 1.00)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Rounded blob body
                RoundedRectangle(cornerRadius: w * 0.32, style: .continuous)
                    .fill(body_)
                    .frame(width: w * 0.74, height: h * 0.70)
                    .position(x: w * 0.5, y: h * 0.58)
                    .shadow(color: PawPalTheme.shadow, radius: 6, y: 4)

                // Pawprint mark on belly
                Image(systemName: "pawprint.fill")
                    .font(.system(size: w * 0.16, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .position(x: w * 0.5, y: h * 0.72)

                // Eyes
                CharacterEyes(mood: mood, spacing: w * 0.17, size: w * 0.07)
                    .position(x: w * 0.5, y: h * 0.44)

                // Mouth
                CharacterMouth(mood: mood, width: w * 0.14)
                    .position(x: w * 0.5, y: h * 0.56)

                // Cheeks
                HStack(spacing: w * 0.44) {
                    Ellipse().fill(PawPalTheme.pink.opacity(0.55))
                        .frame(width: w * 0.09, height: h * 0.04)
                    Ellipse().fill(PawPalTheme.pink.opacity(0.55))
                        .frame(width: w * 0.09, height: h * 0.04)
                }
                .position(x: w * 0.5, y: h * 0.50)
            }
        }
    }
}

// MARK: - Preview

#Preview("Dog — happy") {
    PetCharacterView(species: "Dog", mood: .happy)
        .frame(width: 220, height: 220)
        .background(PawPalTheme.background)
}

#Preview("Cat — sleeping") {
    PetCharacterView(species: "Cat", mood: .sleeping)
        .frame(width: 220, height: 220)
        .background(PawPalTheme.background)
}

#Preview("Rabbit — excited") {
    PetCharacterView(species: "Rabbit", mood: .excited)
        .frame(width: 220, height: 220)
        .background(PawPalTheme.background)
}
