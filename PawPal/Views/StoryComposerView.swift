import PhotosUI
import SwiftUI
import UIKit

/// Full-screen, camera-first composer used to publish an ephemeral (24h)
/// pet story. Modelled on Instagram's story flow:
///
///   1. Appear → immediately present the system camera (via
///      `UIImagePickerController`) so capturing a fresh moment is one
///      tap from the feed rail.
///   2. Dismissing the camera without capturing also dismisses the
///      composer (matches IG — "cancelled capture" = "cancelled story").
///   3. After capture / pick, the user lands on a full-screen preview
///      with a caption field, pet selector, and a publish button. The
///      image fills the viewport under a dark scrim so captions stay
///      legible over any media.
///
/// Gallery fallback: the preview surface has a 🖼 button that opens a
/// `PhotosPicker` for users who want to post something they already
/// have on their camera roll. The simulator, which doesn't have a
/// camera, starts straight on the gallery picker so QA isn't locked
/// out of this flow.
///
/// TODO(video): `matching: .images` on both the system camera and the
/// PhotosPicker — video support lands with the player in `StoryViewerView`.
///
/// Layout rewrite (round 3): the prior sheet-based composer had three
/// reported bugs — the centered title was being cut off at the trailing
/// edge, the X button sat on top of the photo card, and the content
/// below the image read as a blank strip. Switching to a fullscreen
/// dark-scrimmed layout and dropping the title (Instagram doesn't have
/// one either) fixes all three in one pass, and the parent now presents
/// this with `.fullScreenCover` so nothing is eaten by a sheet handle.
struct StoryComposerView: View {
    @Bindable var authManager: AuthManager
    /// Pre-loaded pet set for the current user. Passed in from FeedView
    /// so we don't re-spin up a second PetsService just to render the
    /// chip rail — the feed has already populated its own.
    let pets: [RemotePet]
    /// Called after a successful publish so the caller can dismiss the
    /// cover and (optionally) kick a feed reload.
    let onPublished: () -> Void
    /// Called when the user taps the X / swipes to dismiss without
    /// posting. The caller is responsible for actually dismissing the
    /// cover — this closure is just a notification hook.
    let onCancel: () -> Void

    @ObservedObject private var storyService = StoryService.shared

    @State private var selectedPetID: UUID?
    @State private var caption: String = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var isPosting = false
    @State private var errorMessage: String?

    /// Whether the fullscreen camera is presented. Defaults to true on
    /// devices that actually have a rear camera; simulator + iPads
    /// without one start on the gallery picker instead.
    @State private var showingCamera: Bool = UIImagePickerController.isSourceTypeAvailable(.camera)
    /// Whether the gallery fallback is presented. Opened via the 🖼
    /// button in the preview, and as the initial entry point on
    /// devices without a camera.
    @State private var showingGallery: Bool = false

    /// Matches CreatePostView's 280-char feel. Captions are optional but
    /// we still cap to avoid giant walls of text in the viewer scrim.
    private let captionLimit = 280

    private var selectedPet: RemotePet? {
        pets.first(where: { $0.id == selectedPetID })
    }

    private var canPublish: Bool {
        selectedImageData != nil && selectedPetID != nil && !isPosting
    }

    var body: some View {
        ZStack {
            // Full-screen matte black — this is the Instagram aesthetic
            // and keeps the captured media the hero. Also dodges the
            // layout ambiguity that caused the old sheet's title to get
            // clipped at the trailing edge.
            Color.black.ignoresSafeArea()

            if let data = selectedImageData, let uiImage = UIImage(data: data) {
                previewLayer(uiImage: uiImage)
            } else {
                // Empty state only shows up in the brief window between
                // the composer appearing and the camera sheet presenting
                // (or if the user cancels both entry points without
                // picking anything). A pair of big glyphs keeps the
                // surface from feeling broken.
                emptyEntryLayer
            }
        }
        .task {
            // Default to the user's first pet (matches the "one pet → no
            // selector" branch and keeps the submit button reachable in
            // one tap for the common single-pet case).
            if selectedPetID == nil { selectedPetID = pets.first?.id }

            // Simulator / iPad without camera → auto-open the gallery so
            // the composer isn't a dead screen for QA. Real devices go
            // straight into the camera via `showingCamera`'s default
            // (which reads the same availability flag).
            if !UIImagePickerController.isSourceTypeAvailable(.camera)
                && !showingGallery && selectedImageData == nil {
                showingGallery = true
            }
        }
        .onChange(of: pickerItem) { _, newItem in
            Task { await loadImage(from: newItem) }
        }
        // Camera entry — fullScreenCover so `UIImagePickerController`'s
        // own chrome gets the whole viewport. Presenting `.camera`
        // inside a sheet clips the preview and eats the shutter button.
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(
                onCapture: { image in
                    showingCamera = false
                    if let jpeg = image.jpegData(compressionQuality: 0.9) {
                        selectedImageData = jpeg
                        errorMessage = nil
                    }
                },
                onCancel: {
                    showingCamera = false
                    // If the user cancelled camera AND has no image
                    // queued yet, treat the whole composer as abandoned.
                    // Mirrors Instagram: backing out of camera backs you
                    // out of the story flow entirely.
                    if selectedImageData == nil { onCancel() }
                }
            )
            .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $showingGallery,
            selection: $pickerItem,
            matching: .images
        )
    }

    // MARK: - Preview layer

    /// Full-screen preview shown once a photo has been captured / picked.
    /// Instagram-style layout: media fills the frame, chrome floats over
    /// the top + bottom scrims so the composer reads as a single visual
    /// unit instead of a boxed-in card.
    @ViewBuilder
    private func previewLayer(uiImage: UIImage) -> some View {
        GeometryReader { geo in
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .ignoresSafeArea()

        // Top scrim + header. The gradient fades the hardware status bar
        // into the media and gives the controls a readable backdrop.
        VStack {
            LinearGradient(
                colors: [Color.black.opacity(0.55), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 140)
            .ignoresSafeArea(edges: .top)
            Spacer()
        }

        // Bottom scrim so the caption field + pet chip stay readable over
        // any media. Mirror of the top gradient but reversed.
        VStack {
            Spacer()
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260)
            .ignoresSafeArea(edges: .bottom)
        }

        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 8)

            Spacer(minLength: 0)

            captionComposer
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }

    // MARK: - Empty entry layer

    /// Shown in the brief window before the camera/gallery presents,
    /// or if the user backs out of both without picking media. Gives
    /// them a way back in so the composer is never a dead end.
    private var emptyEntryLayer: some View {
        VStack(spacing: 24) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 8)

            Spacer()

            VStack(spacing: 14) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
                Text("分享 24 小时内自动消失的瞬间")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }

            HStack(spacing: 14) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showingCamera = true
                } label: {
                    entryButton(icon: "camera.fill", label: "拍照")
                }
                .buttonStyle(.plain)
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingGallery = true
                } label: {
                    entryButton(icon: "photo.fill.on.rectangle.fill", label: "相册")
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    private func entryButton(icon: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 110, height: 90)
        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
    }

    // MARK: - Header

    /// Top-bar row shared by the preview and empty-state layers. Plain
    /// X (left) + 发布 (right), with no centered title — which was the
    /// element being clipped at the trailing edge in the old layout.
    private var header: some View {
        HStack(alignment: .center) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.35), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            if selectedImageData != nil {
                Button {
                    Task { await publish() }
                } label: {
                    HStack(spacing: 6) {
                        if isPosting {
                            ProgressView().scaleEffect(0.7)
                                .tint(.white)
                        }
                        Text(isPosting ? "发布中" : "发布")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        canPublish ? PawPalTheme.accent : Color.white.opacity(0.25),
                        in: Capsule()
                    )
                    .animation(.easeInOut(duration: 0.15), value: canPublish)
                }
                .buttonStyle(.plain)
                .disabled(!canPublish)
            }
        }
    }

    // MARK: - Caption composer (bottom overlay)

    private var captionComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Pet chip rail — only shown when the user has >1 pet. For a
            // single-pet household the chip row would be visual noise, so
            // we collapse it to a tiny "发布到 {pet.name}" affordance.
            if pets.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pets) { pet in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedPetID = pet.id
                            } label: {
                                petChipLabel(pet, selected: selectedPetID == pet.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else if let only = pets.first {
                petChipLabel(only, selected: true)
            }

            // Caption field + gallery shortcut, floated over the media.
            HStack(alignment: .center, spacing: 10) {
                TextField(
                    "",
                    text: $caption,
                    prompt: Text("说点什么…").foregroundColor(.white.opacity(0.7)),
                    axis: .vertical
                )
                .lineLimit(1...3)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Color.white.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
                .onChange(of: caption) { _, newValue in
                    if newValue.count > captionLimit {
                        caption = String(newValue.prefix(captionLimit))
                    }
                }

                // Gallery picker — so the user can swap to a saved photo
                // without bailing all the way out of the composer.
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingGallery = true
                } label: {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.14), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))
                }
                .buttonStyle(.plain)

                // Re-capture — shortcut back to the camera. Handy when
                // the shot didn't come out right and the user wants to
                // retry without bailing back out to the feed.
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showingCamera = true
                    } label: {
                        Image(systemName: "camera")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.14), in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.8), in: Capsule())
            }
        }
    }

    // MARK: - Pet chip

    private func petChipLabel(_ pet: RemotePet, selected: Bool) -> some View {
        HStack(spacing: 7) {
            PawPalAvatar(
                emoji: speciesEmoji(for: pet.species ?? ""),
                imageURL: pet.avatar_url,
                size: 24,
                background: selected ? .white.opacity(0.25) : Color.white.opacity(0.18),
                dogBreed: pet.species
            )
            Text(pet.name)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            selected ? PawPalTheme.accent : Color.white.opacity(0.14),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .stroke(selected ? Color.clear : Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: selected ? PawPalTheme.accent.opacity(0.25) : Color.black.opacity(0.1), radius: 6, y: 2)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selected)
    }

    // MARK: - Publish flow

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            selectedImageData = data
            errorMessage = nil
        }
    }

    private func publish() async {
        guard
            let petID = selectedPetID,
            let ownerID = authManager.currentUser?.id,
            let data = selectedImageData
        else { return }

        isPosting = true
        errorMessage = nil
        defer { isPosting = false }

        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await storyService.postStory(
            petID: petID,
            ownerID: ownerID,
            mediaData: data,
            mediaType: "image",
            caption: trimmed.isEmpty ? nil : trimmed
        )

        if result != nil {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onPublished()
        } else {
            // Surface the service's latest message, falling back to a
            // generic string so the user never sees a silent failure.
            errorMessage = storyService.errorMessage ?? "发布失败，请稍后再试"
        }
    }

    // MARK: - Helpers

    private func speciesEmoji(for species: String) -> String {
        switch species.lowercased() {
        case "dog":             return "🐶"
        case "cat":             return "🐱"
        case "rabbit", "bunny": return "🐰"
        case "bird":            return "🦜"
        case "hamster":         return "🐹"
        case "fish":            return "🐟"
        default:                return "🐾"
        }
    }
}

// MARK: - Camera picker bridge

/// Thin `UIViewControllerRepresentable` wrapper around
/// `UIImagePickerController` configured for live camera capture. We use
/// this instead of SwiftUI's `PhotosPicker` because PhotosPicker targets
/// the photo library — there's no first-party SwiftUI surface for the
/// system camera as of iOS 18, so the UIKit bridge is load-bearing.
///
/// `cameraCaptureMode = .photo` keeps this image-only for the MVP.
/// TODO(video): add a `mediaTypes` toggle when the story viewer learns
/// to render video.
private struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}
