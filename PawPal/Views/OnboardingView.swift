import SwiftUI
import PhotosUI
import UIKit

/// First-run onboarding gate. Shown full-screen in place of `MainTabView`
/// when a signed-in user has zero pets. Collects the minimum pet data we
/// need (name required, species defaulting to Dog, everything else
/// optional) and calls `PetsService.shared.addPet` to land the first pet
/// before the user ever sees the Feed. No skip affordance — product.md
/// opens with "Pets are the protagonists" and an empty-pet account
/// can't participate in the social graph, so onboarding is a hard gate
/// rather than a nudge.
///
/// Design cues are borrowed from `ProfilePetEditorSheet` (same fields,
/// same species chip row) and `AuthView` (warm full-screen brand
/// treatment). We intentionally replicate the form inline rather than
/// extracting a shared subview: the onboarding flow needs exactly the
/// six fields listed in the spec (name / species / breed / city / bio /
/// avatar) whereas the profile editor carries sex / age / weight too,
/// and pulling those apart cleanly would mean touching ProfileView.swift
/// — which is owned by Dev 1. Inline replication keeps the blast radius
/// inside our owned files.
struct OnboardingView: View {

    let userID: UUID

    /// Fires after `addPet` succeeds. The parent (`MainTabView`) doesn't
    /// actually need this — its gating condition flips false as soon as
    /// `petsService.pets` becomes non-empty — but we pass the closure
    /// through so the haptic + any future side effects live in one
    /// place.
    var onComplete: () -> Void = {}

    // MARK: Form state

    @State private var name = ""
    @State private var species = "Dog"
    @State private var breed = ""
    @State private var city = ""
    @State private var bio = ""

    @State private var pickedAvatarItem: PhotosPickerItem?
    @State private var pickedAvatarData: Data?
    @State private var pickedAvatarImage: Image?

    @State private var isSaving = false
    @State private var errorMessage: String?

    /// Controls presentation of the notification-permission priming
    /// sheet. Flipped true immediately after `addPet` succeeds —
    /// matches the PM doc's "yes, after successful pet creation" rule
    /// in `docs/sessions/2026-04-18-pm-push-notifications.md`. The
    /// sheet is a gentle wrapper around the system prompt, presented
    /// here (rather than on cold start or post-auth) so the user has
    /// already invested in the product before we ask.
    @State private var showingNotificationPriming = false

    @ObservedObject private var petsService = PetsService.shared

    private let speciesOptions: [(emoji: String, label: String)] = [
        ("🐶", "Dog"), ("🐱", "Cat")
    ]

    var body: some View {
        ZStack {
            PawPalBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header
                        .padding(.top, 24)

                    avatarPickerBlock

                    formCard

                    bioCard

                    if let errorMessage {
                        errorLine(errorMessage)
                    }

                    submitButton
                        .padding(.top, 4)

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        // Post-pet priming sheet. Full-screen cover so the copy has
        // room to breathe and the user can't dismiss-by-drag in a
        // half-committed state. After it's dismissed (either outcome),
        // `onComplete` fires and MainTabView's gating flips to the
        // tab bar.
        .fullScreenCover(isPresented: $showingNotificationPriming, onDismiss: handlePrimingDismissed) {
            NotificationPrimingView(
                onPrimary: {
                    _ = await PushService.shared.requestAuthorization()
                    showingNotificationPriming = false
                },
                onSecondary: {
                    showingNotificationPriming = false
                }
            )
        }
    }

    /// Fires when the priming sheet finishes dismissing (either the
    /// primary button, the 以后再说 secondary, or an SDK-level
    /// dismissal). Records that we've primed this device so future
    /// sign-ins on the same install don't re-ask, then forwards to
    /// the parent completion so MainTabView can swap us out for the
    /// tab bar.
    private func handlePrimingDismissed() {
        UserDefaults.standard.set(true, forKey: "pawpal.push.primed")
        onComplete()
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [PawPalTheme.accent, PawPalTheme.accentSoft],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: PawPalTheme.accent.opacity(0.38), radius: 18, y: 8)
                Text("🐾")
                    .font(.system(size: 34))
            }

            Text("欢迎来到 PawPal 🐾")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
                .multilineTextAlignment(.center)

            Text("先介绍一下你的毛孩子吧")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(PawPalTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Avatar picker

    private var avatarPickerBlock: some View {
        PhotosPicker(
            selection: $pickedAvatarItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            ZStack(alignment: .bottomTrailing) {
                avatarPreview
                Image(systemName: "camera.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(PawPalTheme.accent, in: Circle())
                    .offset(x: 4, y: 4)
            }
        }
        .buttonStyle(.plain)
        .onChange(of: pickedAvatarItem) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                pickedAvatarData = data
                if let uiImage = UIImage(data: data) {
                    pickedAvatarImage = Image(uiImage: uiImage)
                }
            }
        }
    }

    private var avatarPreview: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [PawPalTheme.accent.opacity(0.2), PawPalTheme.cardSoft],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 96, height: 96)

            if let pickedAvatarImage {
                pickedAvatarImage
                    .resizable().scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())
            } else {
                Text(speciesEmoji(for: species))
                    .font(.system(size: 48))
                    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: species)
            }
        }
        .overlay(
            Circle().stroke(PawPalTheme.accent.opacity(0.35), lineWidth: 3)
        )
        .shadow(color: PawPalTheme.accent.opacity(0.18), radius: 14, y: 6)
    }

    // MARK: - Form

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("宠物类别")
            speciesChipRow

            VStack(spacing: 0) {
                fieldRow(label: "名字", required: true) {
                    TextField("宠物名字", text: $name)
                }
                Divider().padding(.leading, 16)
                fieldRow(label: "品种") {
                    TextField("例如：金毛", text: $breed)
                        .multilineTextAlignment(.trailing)
                }
                Divider().padding(.leading, 16)
                fieldRow(label: "家乡") {
                    TextField("例如：上海", text: $city)
                        .multilineTextAlignment(.trailing)
                }
            }
            .background(PawPalTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(PawPalTheme.hairline, lineWidth: 0.5)
            )
        }
    }

    private var speciesChipRow: some View {
        HStack(spacing: 10) {
            ForEach(speciesOptions, id: \.label) { option in
                speciesChip(option)
            }
            Spacer(minLength: 0)
        }
    }

    private func speciesChip(_ option: (emoji: String, label: String)) -> some View {
        let selected = species == option.label
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                species = option.label
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 6) {
                Text(option.emoji)
                    .font(.system(size: 28))
                Text(speciesDisplayName(option.label))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(selected ? .white : PawPalTheme.secondaryText)
            }
            .frame(width: 76, height: 78)
            .background(
                selected
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [PawPalTheme.accent, PawPalTheme.accentSoft],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    : AnyShapeStyle(PawPalTheme.card),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Color.clear : PawPalTheme.hairline, lineWidth: 0.5)
            )
            .shadow(
                color: selected ? PawPalTheme.accent.opacity(0.3) : PawPalTheme.softShadow,
                radius: selected ? 10 : 4, y: selected ? 5 : 2
            )
            .scaleEffect(selected ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: selected)
    }

    private var bioCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("简介")
            TextField("简单介绍一下你的毛孩子…", text: $bio, axis: .vertical)
                .lineLimit(3...5)
                .font(.system(size: 16))
                .padding(16)
                .background(PawPalTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(PawPalTheme.hairline, lineWidth: 0.5)
                )
        }
    }

    // MARK: - Submit

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(canSubmit
                          ? LinearGradient(colors: [PawPalTheme.accent, PawPalTheme.accentSoft], startPoint: .leading, endPoint: .trailing)
                          : LinearGradient(colors: [Color(.tertiarySystemFill), Color(.tertiarySystemFill)], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 56)
                    .shadow(color: canSubmit ? PawPalTheme.accent.opacity(0.42) : .clear, radius: 18, y: 8)

                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Text("开始使用 PawPal")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(canSubmit ? .white : .secondary)
                }
            }
        }
        .disabled(!canSubmit || isSaving)
        .animation(.easeInOut(duration: 0.15), value: canSubmit)
        .accessibilityIdentifier("onboarding-submit-button")
    }

    private func errorLine(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(PawPalTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Helpers

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit, !isSaving else { return }
        isSaving = true
        errorMessage = nil

        Task {
            let saved = await petsService.addPet(
                for: userID,
                name: name,
                species: species,
                breed: breed,
                sex: "",
                age: "",
                weight: "",
                homeCity: city,
                bio: bio,
                avatarData: pickedAvatarData
            )
            isSaving = false

            if saved != nil {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                // Present the notification priming sheet unless we've
                // already primed this device (returning user who added
                // another pet shouldn't re-see the prompt). When the
                // sheet dismisses, `handlePrimingDismissed` fires
                // `onComplete` for us — at which point MainTabView's
                // gating flips because `petsService.pets` is non-empty.
                if UserDefaults.standard.bool(forKey: "pawpal.push.primed") {
                    onComplete()
                } else {
                    showingNotificationPriming = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    errorMessage = "创建失败，请重试"
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .tracking(0.4)
            .foregroundStyle(PawPalTheme.secondaryText)
            .padding(.horizontal, 4)
    }

    private func fieldRow<C: View>(
        label: String,
        required: Bool = false,
        @ViewBuilder content: () -> C
    ) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                if required {
                    Text("*")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(PawPalTheme.accent)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 8)

            content()
                .font(.system(size: 15))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func speciesEmoji(for species: String) -> String {
        switch species {
        case "Dog": return "🐶"
        case "Cat": return "🐱"
        default:    return "🐾"
        }
    }

    private func speciesDisplayName(_ english: String) -> String {
        switch english {
        case "Dog": return "狗狗"
        case "Cat": return "猫咪"
        default:    return "其他"
        }
    }
}

// MARK: - NotificationPrimingView
//
// Warm, product-voice sell for the iOS push prompt. Presented AFTER
// the first pet is persisted — at which point the user has already
// invested in the app and we can speak in concrete terms ("你的毛孩子
// 有了新朋友"). Copy is verbatim from
// `docs/sessions/2026-04-18-pm-push-notifications.md`. Tapping the
// primary button funnels into `PushService.requestAuthorization()`
// which triggers the system prompt; the secondary just dismisses.

/// Permission-priming sheet shown full-screen right after the user
/// saves their first pet. Never drives the OS prompt directly — all
/// the logic lives in `PushService.requestAuthorization()` so the
/// priming view is a pure presentation layer that can be re-used from
/// a future Settings re-prompt surface.
struct NotificationPrimingView: View {

    /// Invoked when the user taps 开启通知. Receives the async call
    /// so the parent can await the grant result before dismissing.
    var onPrimary: () async -> Void

    /// Invoked when the user taps 以后再说. No OS call — just a
    /// dismiss signal to the parent.
    var onSecondary: () -> Void

    @State private var isRequesting = false

    var body: some View {
        ZStack {
            PawPalBackground()
                .ignoresSafeArea()

            VStack(spacing: PawPalSpacing.xxl) {
                Spacer(minLength: PawPalSpacing.xxl)

                heroGlyph

                VStack(spacing: PawPalSpacing.md) {
                    Text("让 PawPal 第一时间告诉你")
                        .font(PawPalFont.serif(size: 26, weight: .semibold))
                        .foregroundStyle(PawPalTheme.primaryText)
                        .multilineTextAlignment(.center)

                    Text("开启通知,你的毛孩子有了新朋友、别人给了小爱心或评论,我们会悄悄提醒你。生日和遛弯约会也不会错过。")
                        .font(PawPalFont.ui(size: 15, weight: .regular))
                        .foregroundStyle(PawPalTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, PawPalSpacing.lg)
                }
                .padding(.horizontal, PawPalSpacing.xl)

                Spacer()

                VStack(spacing: PawPalSpacing.md) {
                    primaryButton
                    secondaryButton
                }
                .padding(.horizontal, PawPalSpacing.xl)
                .padding(.bottom, PawPalSpacing.xxl)
            }
        }
    }

    // MARK: - Subviews

    private var heroGlyph: some View {
        ZStack {
            Circle()
                .fill(PawPalTheme.gradientOrangeToSoft)
                .frame(width: 96, height: 96)
                .shadow(color: PawPalTheme.accent.opacity(0.35), radius: 22, y: 10)
            Text("🔔")
                .font(.system(size: 56))
        }
    }

    private var primaryButton: some View {
        Button {
            guard !isRequesting else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isRequesting = true
            Task {
                await onPrimary()
                isRequesting = false
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: PawPalRadius.lg, style: .continuous)
                    .fill(PawPalTheme.gradientOrangeToSoft)
                    .frame(height: 56)
                    .shadow(color: PawPalTheme.accent.opacity(0.4), radius: 18, y: 8)

                if isRequesting {
                    ProgressView().tint(.white)
                } else {
                    Text("开启通知")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .disabled(isRequesting)
        .accessibilityIdentifier("notification-priming-primary")
    }

    private var secondaryButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSecondary()
        } label: {
            Text("以后再说")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(PawPalTheme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, PawPalSpacing.md)
        }
        .disabled(isRequesting)
        .accessibilityIdentifier("notification-priming-secondary")
    }
}
