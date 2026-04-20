import SwiftUI

/// One-shot sheet surfaced from `FeedView.onAppear` when any playdate
/// completed within the last 4h and the corresponding UserDefaults flag
/// hasn't been set yet. Either CTA flips the flag so the prompt never
/// shows twice for the same playdate.
///
/// Copy per §5.6 / §7 of
/// `docs/sessions/2026-04-18-pm-playdates-mvp-execution.md`.
struct PostPlaydatePromptSheet: View {
    let playdate: RemotePlaydate
    let otherPetName: String
    let proposerPetID: UUID
    let inviteePetID: UUID
    let onDismiss: () -> Void
    /// Upstream (`FeedView`) wires this into its `composerPrefill`
    /// `sheet(item:)` so the post composer picks up both the prefill
    /// caption and the pet-ids. See the follow-up note on `ComposerPrefill`
    /// — multi-pet attachment ships behind `pets:` while this call site
    /// defaults to the viewer's own pet id for single-pet safety.
    let onStartPost: (ComposerPrefill) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Caption baked from the spec — "今天和 {other_pet_name} 一起遛弯 🐾".
    private var prefillCaption: String {
        "今天和 \(otherPetName) 一起遛弯 🐾"
    }

    var body: some View {
        ZStack {
            PawPalBackground()

            VStack(spacing: 0) {
                Capsule()
                    .fill(PawPalTheme.hairline)
                    .frame(width: 40, height: 4)
                    .padding(.top, 8)
                    .padding(.bottom, 18)

                VStack(spacing: 10) {
                    Text("📷")
                        .font(.system(size: 40))
                    Text("和 \(otherPetName) 的遛弯怎么样?")
                        .font(PawPalFont.rounded(size: 22, weight: .bold))
                        .foregroundStyle(PawPalTheme.primaryText)
                        .multilineTextAlignment(.center)
                    Text("发一条遛弯日记，把今天的照片分享出来吧")
                        .font(.system(size: 14))
                        .foregroundStyle(PawPalTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)

                Spacer(minLength: 20)

                VStack(spacing: 10) {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        markSeen()
                        // Multi-pet attachment (both pets tagged) is a
                        // follow-up per spec §5.6 note. For now, seed the
                        // composer with the proposer pet id — the viewer's
                        // own pet — and the full caption.
                        let prefill = ComposerPrefill(
                            petID: proposerPetID,
                            caption: prefillCaption,
                            pets: [proposerPetID, inviteePetID]
                        )
                        onStartPost(prefill)
                        dismiss()
                    } label: {
                        Text("发一条遛弯日记")
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

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        markSeen()
                        onDismiss()
                        dismiss()
                    } label: {
                        Text("以后再说")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(PawPalTheme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }

    private func markSeen() {
        UserDefaults.standard.set(true, forKey: "pawpal.playdate.prompt.\(playdate.id.uuidString)")
    }
}
