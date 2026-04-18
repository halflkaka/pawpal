import SwiftUI

/// Stylised geometric dog avatar — used as a fallback when a real pet photo
/// hasn't been uploaded yet, and as decorative ornament throughout the app.
///
/// Mirrors the `DogAvatar` component in the design prototype, including its
/// breed palettes, accessories (bow, hat, glasses), and "happy / sleepy"
/// expressions. SVGs are reproduced as SwiftUI shapes so they vector-scale
/// crisply at any size.
struct DogAvatar: View {

    // MARK: Variants & accessories

    enum Variant: String, CaseIterable {
        case golden, corgi, husky, shiba, beagle, poodle, pug

        /// Picks a sensible variant from a free-form breed string. Keeps both
        /// the English breed names (matching the prototype) and the Chinese
        /// breed labels users pick from `CreatePostView` working.
        static func from(breed: String?) -> Variant {
            guard let breed = breed?.lowercased(), !breed.isEmpty else { return .golden }
            // Match common English & Chinese strings.
            if breed.contains("corgi") || breed.contains("柯基") { return .corgi }
            if breed.contains("husky") || breed.contains("哈士奇") || breed.contains("二哈") { return .husky }
            if breed.contains("shiba") || breed.contains("柴") { return .shiba }
            if breed.contains("beagle") || breed.contains("比格") { return .beagle }
            if breed.contains("poodle") || breed.contains("贵宾") || breed.contains("泰迪") { return .poodle }
            if breed.contains("pug") || breed.contains("巴哥") || breed.contains("八哥") { return .pug }
            return .golden
        }
    }

    enum Accessory: String, CaseIterable {
        case none, bow, hat, glasses
    }

    enum Expression: String {
        case happy, sleepy
    }

    fileprivate struct Palette {
        let body: Color
        let ear: Color
        let muzzle: Color
        let spot: Color?
    }

    // MARK: Inputs

    var variant: Variant = .golden
    var size: CGFloat = 56
    var background: Color = Color(red: 1.00, green: 0.953, blue: 0.902)  // #FFF3E6
    var accessory: Accessory = .none
    var expression: Expression = .happy

    // MARK: Body

    var body: some View {
        let p = palette(for: variant)
        ZStack {
            Circle().fill(background)
            DogFace(palette: p, expression: expression)
                .frame(width: size * 0.92, height: size * 0.92)
            accessoryOverlay
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    @ViewBuilder
    private var accessoryOverlay: some View {
        switch accessory {
        case .none:
            EmptyView()
        case .bow:
            Text("🎀")
                .font(.system(size: size * 0.28))
                .offset(x: size * 0.18, y: -size * 0.32)
        case .hat:
            Text("🎩")
                .font(.system(size: size * 0.32))
                .offset(x: -size * 0.05, y: -size * 0.42)
        case .glasses:
            // Two small circles + bridge in ink. Positioned over the eyes.
            HStack(spacing: size * 0.04) {
                Circle()
                    .strokeBorder(Color(red: 0.165, green: 0.141, blue: 0.125), lineWidth: max(1.2, size * 0.025))
                    .background(Circle().fill(Color.white.opacity(0.18)))
                    .frame(width: size * 0.20, height: size * 0.20)
                Circle()
                    .strokeBorder(Color(red: 0.165, green: 0.141, blue: 0.125), lineWidth: max(1.2, size * 0.025))
                    .background(Circle().fill(Color.white.opacity(0.18)))
                    .frame(width: size * 0.20, height: size * 0.20)
            }
            .overlay(
                Rectangle()
                    .fill(Color(red: 0.165, green: 0.141, blue: 0.125))
                    .frame(width: size * 0.05, height: max(1.2, size * 0.022))
            )
            .offset(y: -size * 0.05)
        }
    }

    // MARK: Palettes

    private func palette(for variant: Variant) -> Palette {
        switch variant {
        case .golden:
            return Palette(
                body:   Color(red: 0.910, green: 0.718, blue: 0.478),  // #E8B77A
                ear:    Color(red: 0.784, green: 0.604, blue: 0.361),  // #C89A5C
                muzzle: Color(red: 0.961, green: 0.875, blue: 0.710),  // #F5DFB5
                spot:   nil
            )
        case .corgi:
            return Palette(
                body:   Color(red: 0.910, green: 0.655, blue: 0.400),  // #E8A766
                ear:    .white,
                muzzle: .white,
                spot:   Color(red: 0.910, green: 0.655, blue: 0.400)
            )
        case .husky:
            return Palette(
                body:   Color(red: 0.847, green: 0.847, blue: 0.863),  // #D8D8DC
                ear:    Color(red: 0.227, green: 0.227, blue: 0.227),  // #3A3A3A
                muzzle: .white,
                spot:   Color(red: 0.227, green: 0.227, blue: 0.227)
            )
        case .shiba:
            return Palette(
                body:   Color(red: 0.851, green: 0.565, blue: 0.353),  // #D9905A
                ear:    Color(red: 0.722, green: 0.451, blue: 0.251),  // #B87340
                muzzle: Color(red: 0.969, green: 0.894, blue: 0.812),  // #F7E4CF
                spot:   nil
            )
        case .beagle:
            return Palette(
                body:   Color(red: 0.941, green: 0.882, blue: 0.784),  // #F0E1C8
                ear:    Color(red: 0.482, green: 0.290, blue: 0.165),  // #7B4A2A
                muzzle: .white,
                spot:   Color(red: 0.482, green: 0.290, blue: 0.165)
            )
        case .poodle:
            return Palette(
                body:   Color(red: 0.180, green: 0.165, blue: 0.165),  // #2E2A2A
                ear:    Color(red: 0.180, green: 0.165, blue: 0.165),
                muzzle: Color(red: 0.290, green: 0.271, blue: 0.271),  // #4A4545
                spot:   nil
            )
        case .pug:
            return Palette(
                body:   Color(red: 0.878, green: 0.769, blue: 0.561),  // #E0C48F
                ear:    Color(red: 0.227, green: 0.180, blue: 0.157),  // #3A2E28
                muzzle: Color(red: 0.227, green: 0.180, blue: 0.157),
                spot:   nil
            )
        }
    }
}

// MARK: - Vector face

/// SwiftUI port of the SVG dog face. Drawn as paths inside a Canvas-style
/// `ZStack` of shapes so it scales crisply.
private struct DogFace: View {
    let palette: DogAvatar.Palette
    let expression: DogAvatar.Expression

    var body: some View {
        GeometryReader { geo in
            // Use a 100x100 design grid and scale.
            let s = min(geo.size.width, geo.size.height) / 100.0
            let ink = Color(red: 0.165, green: 0.141, blue: 0.125)  // #2A2420
            let eyeY: CGFloat = (expression == .sleepy) ? 56 : 54

            ZStack {
                // Ears
                Ellipse()
                    .fill(palette.ear)
                    .frame(width: 22 * s, height: 32 * s)
                    .rotationEffect(.degrees(-20), anchor: .center)
                    .position(x: 26 * s, y: 38 * s)

                Ellipse()
                    .fill(palette.ear)
                    .frame(width: 22 * s, height: 32 * s)
                    .rotationEffect(.degrees(20), anchor: .center)
                    .position(x: 74 * s, y: 38 * s)

                // Head
                Circle()
                    .fill(palette.body)
                    .frame(width: 52 * s, height: 52 * s)
                    .position(x: 50 * s, y: 52 * s)

                // Spot
                if let spot = palette.spot {
                    Ellipse()
                        .fill(spot.opacity(0.9))
                        .frame(width: 16 * s, height: 14 * s)
                        .position(x: 32 * s, y: 44 * s)
                }

                // Muzzle
                Ellipse()
                    .fill(palette.muzzle)
                    .frame(width: 28 * s, height: 20 * s)
                    .position(x: 50 * s, y: 64 * s)

                // Nose
                Ellipse()
                    .fill(ink)
                    .frame(width: 6.4 * s, height: 4.8 * s)
                    .position(x: 50 * s, y: 60 * s)

                // Mouth (two short curves)
                MouthCurve()
                    .stroke(ink, style: StrokeStyle(lineWidth: 1.4 * s, lineCap: .round))
                    .frame(width: 16 * s, height: 8 * s)
                    .position(x: 50 * s, y: 65 * s)

                // Tongue
                if expression == .happy {
                    Ellipse()
                        .fill(Color(red: 0.933, green: 0.533, blue: 0.533))  // #E88
                        .frame(width: 6 * s, height: 4 * s)
                        .position(x: 50 * s, y: 69 * s)
                }

                // Eyes
                if expression == .sleepy {
                    SleepyEye()
                        .stroke(ink, style: StrokeStyle(lineWidth: 2.5 * s, lineCap: .round))
                        .frame(width: 12 * s, height: 4 * s)
                        .position(x: 42 * s, y: eyeY * s)
                    SleepyEye()
                        .stroke(ink, style: StrokeStyle(lineWidth: 2.5 * s, lineCap: .round))
                        .frame(width: 12 * s, height: 4 * s)
                        .position(x: 58 * s, y: eyeY * s)
                } else {
                    eyeDot(at: CGPoint(x: 42 * s, y: eyeY * s), radius: 2.8 * s, ink: ink)
                    eyeDot(at: CGPoint(x: 58 * s, y: eyeY * s), radius: 2.8 * s, ink: ink)
                }
            }
        }
    }

    @ViewBuilder
    private func eyeDot(at point: CGPoint, radius: CGFloat, ink: Color) -> some View {
        ZStack {
            Circle()
                .fill(ink)
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .fill(Color.white)
                .frame(width: radius * 0.6, height: radius * 0.6)
                .offset(x: 0, y: -radius * 0.3)
        }
        .position(point)
    }
}

// MARK: - Shapes

private struct MouthCurve: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mid = CGPoint(x: rect.midX, y: rect.minY)
        let leftEnd = CGPoint(x: rect.minX, y: rect.maxY)
        let rightEnd = CGPoint(x: rect.maxX, y: rect.maxY)
        path.move(to: mid)
        path.addQuadCurve(
            to: leftEnd,
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        path.move(to: mid)
        path.addQuadCurve(
            to: rightEnd,
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        return path
    }
}

private struct SleepyEye: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.3)
        )
        return path
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 16) {
            DogAvatar(variant: .golden, size: 72)
            DogAvatar(variant: .corgi, size: 72, accessory: .bow)
            DogAvatar(variant: .husky, size: 72, accessory: .glasses)
            DogAvatar(variant: .shiba, size: 72)
        }
        HStack(spacing: 16) {
            DogAvatar(variant: .beagle, size: 72)
            DogAvatar(variant: .poodle, size: 72, accessory: .hat)
            DogAvatar(variant: .pug, size: 72, expression: .sleepy)
            DogAvatar(variant: .golden, size: 72, expression: .sleepy)
        }
    }
    .padding()
    .background(PawPalTheme.background)
}
