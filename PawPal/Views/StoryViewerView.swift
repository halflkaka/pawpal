import SwiftUI
import UIKit

/// Bundle of one pet and their ordered (oldest-first) active stories.
/// Used as the input shape for `StoryViewerView` — decouples the viewer
/// from any live service state so it can be driven by a snapshot.
struct PetStoriesBundle: Identifiable, Equatable {
    let pet: RemotePet
    let stories: [RemoteStory]
    var id: UUID { pet.id }

    static func == (lhs: PetStoriesBundle, rhs: PetStoriesBundle) -> Bool {
        lhs.pet.id == rhs.pet.id && lhs.stories.map(\.id) == rhs.stories.map(\.id)
    }
}

/// Fullscreen tap-through story viewer. Instagram-style: a black
/// canvas with progress bars across the top, tap-right-to-advance,
/// tap-left-to-go-back, and long-press-to-pause.
///
/// Navigation model: the viewer receives a pre-built array of
/// `PetStoriesBundle`s plus an `initialPetIndex` so the caller can
/// decide ordering (own pets first, etc.). Internally we track the
/// current pet index and the current story index within that pet's
/// stack; running off the end of the last pet dismisses the viewer.
///
/// TODO(video): `media_type == "video"` stories currently render the
/// video URL through `AsyncImage`, which only renders it as a still
/// if the server returns a poster URL. When video playback lands we
/// swap in an `AVPlayerLayer`-backed view and key the progress timer
/// off the actual asset duration instead of the fixed 5s fallback.
struct StoryViewerView: View {
    let petsWithStories: [PetStoriesBundle]
    let initialPetIndex: Int
    let currentUserID: UUID?
    let onDismiss: () -> Void

    @ObservedObject private var storyService = StoryService.shared
    /// Used to resolve the "viewing as" pet when recording a view for
    /// non-owner stories. MVP picks `pets.first` — see `recordViewIfNeeded`.
    @ObservedObject private var petsService = PetsService.shared

    @State private var petIndex: Int
    @State private var storyIndex: Int = 0
    /// 0...1 fill of the *current* story's progress bar. Older bars
    /// are rendered as fully filled, newer ones as empty — avoids
    /// having to track per-bar state.
    @State private var progress: CGFloat = 0
    @State private var isPaused: Bool = false
    @State private var dragOffset: CGFloat = 0

    // MARK: - View-receipt state (migration 024)

    /// Dedupes the "record this view" side-effect so we call
    /// `StoryService.recordView` at most once per story per viewer
    /// session. The viewer may oscillate back and forth through the
    /// tap zones — we don't want to spam inserts (the DB `ON
    /// CONFLICT DO NOTHING` would swallow them anyway, but a
    /// client-side guard skips the round-trip entirely).
    @State private var recordedViewIDs: Set<UUID> = []

    /// Owner-only per-story viewer count cache. Populated lazily as
    /// the owner tap-throughs their own stack. Keyed by story id so
    /// flipping back and forth between stories doesn't re-fetch.
    @State private var viewerCounts: [UUID: Int] = [:]

    /// Story id whose viewer sheet is currently presented. Keys the
    /// `.sheet(item:)` modifier so SwiftUI re-inits
    /// `StoryViewersSheet` when the owner opens it on a new story
    /// without dismissing in between.
    @State private var activeViewerSheetStoryID: StoryIdentifier?

    /// Fixed duration per image story. Matches Instagram / most
    /// stories UIs and is long enough to read a caption.
    private let storyDuration: TimeInterval = 5.0
    /// Drives the progress bar. Every tick advances `progress` by
    /// `tickInterval / storyDuration`. TimelineView would give us a
    /// similar effect but Timer.publish is dead-simple to pause.
    private let tickInterval: TimeInterval = 0.05

    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    init(
        petsWithStories: [PetStoriesBundle],
        initialPetIndex: Int,
        currentUserID: UUID?,
        onDismiss: @escaping () -> Void
    ) {
        self.petsWithStories = petsWithStories
        self.initialPetIndex = max(0, min(initialPetIndex, max(0, petsWithStories.count - 1)))
        self.currentUserID = currentUserID
        self.onDismiss = onDismiss
        _petIndex = State(initialValue: self.initialPetIndex)
    }

    private var currentBundle: PetStoriesBundle? {
        guard petsWithStories.indices.contains(petIndex) else { return nil }
        return petsWithStories[petIndex]
    }

    private var currentStory: RemoteStory? {
        guard let bundle = currentBundle,
              bundle.stories.indices.contains(storyIndex) else { return nil }
        return bundle.stories[storyIndex]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let bundle = currentBundle, let story = currentStory {
                storyMedia(for: story)
                    .ignoresSafeArea()

                // Bottom scrim + caption. Sits above the media but below
                // the tap zones so the caption never eats a tap.
                VStack(spacing: 0) {
                    Spacer()
                    if let caption = story.caption, !caption.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(caption)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineSpacing(3)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 60)
                                .padding(.top, 32)
                        }
                        .background(
                            LinearGradient(
                                colors: [Color.black.opacity(0.0), Color.black.opacity(0.55)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                // Tap zones — sit above the media so taps land here, not
                // on the AsyncImage. Left half = back, right half = next.
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            goPrevious()
                        }
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            goNext()
                        }
                }
                // Long-press-to-pause sits on the whole canvas. Using a
                // DragGesture with 0 distance lets us capture press-down
                // and press-up cleanly without fighting the tap gestures
                // above (SwiftUI prioritises the more specific tap).
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.18)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .onChanged { _ in isPaused = true }
                        .onEnded { _ in isPaused = false }
                )

                // Header — progress bars + pet avatar + dismiss/delete.
                VStack(spacing: 10) {
                    progressBars(for: bundle)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    headerRow(for: bundle, story: story)
                        .padding(.horizontal, 16)
                    Spacer()
                }

                // Owner-only "看过" footer chip. Sits above the safe-
                // area inset, below the caption scrim. Tappable —
                // opens the viewer list sheet. Hidden for non-owners.
                if isOwner(of: story) {
                    VStack(spacing: 0) {
                        Spacer()
                        viewerCountChip(for: story)
                            .padding(.bottom, 16)
                    }
                }
            } else {
                // Empty-state fallback — shouldn't be reachable through
                // the UI, but protects against a caller passing an empty
                // bundle list.
                VStack(spacing: 12) {
                    Text("没有故事了 🐾")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Button("关闭") { onDismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
        // Swipe-down to dismiss. Translation-only drag so we don't
        // intercept the horizontal tap zones.
        .offset(y: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 120 {
                        onDismiss()
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
        )
        .onReceive(timer) { _ in
            tickProgress()
        }
        .onAppear {
            // Fire the receipt-record / count-load for the initial
            // story on present. Subsequent stories are handled by the
            // onChange hooks below.
            handleStoryBecameActive()
        }
        .onChange(of: petIndex) { _, _ in
            progress = 0
            handleStoryBecameActive()
        }
        .onChange(of: storyIndex) { _, _ in
            progress = 0
            handleStoryBecameActive()
        }
        .sheet(item: $activeViewerSheetStoryID) { identifier in
            StoryViewersSheet(storyID: identifier.id)
        }
        .statusBarHidden(true)
    }

    // MARK: - Media

    @ViewBuilder
    private func storyMedia(for story: RemoteStory) -> some View {
        if let url = URL(string: story.media_url) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failure:
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("加载失败")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                default:
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: - Header

    private func progressBars(for bundle: PetStoriesBundle) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(bundle.stories.enumerated()), id: \.element.id) { idx, _ in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.35))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: geo.size.width * fillFraction(for: idx))
                    }
                }
                .frame(height: 3)
            }
        }
    }

    private func fillFraction(for barIndex: Int) -> CGFloat {
        if barIndex < storyIndex { return 1.0 }
        if barIndex == storyIndex { return progress }
        return 0.0
    }

    private func headerRow(for bundle: PetStoriesBundle, story: RemoteStory) -> some View {
        HStack(spacing: 10) {
            PawPalAvatar(
                emoji: speciesEmoji(for: bundle.pet.species ?? ""),
                imageURL: bundle.pet.avatar_url,
                size: 32,
                background: PawPalTheme.cardSoft,
                dogBreed: bundle.pet.species
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(bundle.pet.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(relativeTime(from: story.created_at))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
            }

            Spacer()

            // Delete affordance — only for the story owner.
            if let me = currentUserID, story.owner_user_id == me {
                Button {
                    Task { await deleteCurrentStory(story) }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.18), in: Circle())
                }
                .buttonStyle(.plain)
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Progress / navigation

    private func tickProgress() {
        guard !isPaused, currentStory != nil else { return }
        let delta = CGFloat(tickInterval / storyDuration)
        let next = progress + delta
        if next >= 1.0 {
            progress = 1.0
            goNext()
        } else {
            progress = next
        }
    }

    private func goNext() {
        guard let bundle = currentBundle else {
            onDismiss()
            return
        }
        if storyIndex < bundle.stories.count - 1 {
            storyIndex += 1
            return
        }
        // End of this pet's stack — advance to next pet, or dismiss.
        if petIndex < petsWithStories.count - 1 {
            petIndex += 1
            storyIndex = 0
        } else {
            onDismiss()
        }
    }

    private func goPrevious() {
        if storyIndex > 0 {
            storyIndex -= 1
            return
        }
        // Already at the first story for this pet — jump back to the
        // previous pet's last story. If there's no previous pet, just
        // restart the current story.
        if petIndex > 0 {
            petIndex -= 1
            storyIndex = max(0, (petsWithStories[petIndex].stories.count) - 1)
        } else {
            progress = 0
        }
    }

    private func deleteCurrentStory(_ story: RemoteStory) async {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let ok = await storyService.deleteStory(storyID: story.id)
        guard ok else { return }
        // Simplest correct behaviour: close the viewer. The rail will
        // re-render off the live StoryService cache, so the ring drops
        // away without any extra state shuffling here.
        onDismiss()
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

    private func relativeTime(from date: Date) -> String {
        let s = max(0, Int(-date.timeIntervalSinceNow))
        if s < 60     { return "刚刚" }
        if s < 3600   { return "\(s / 60)分钟前" }
        if s < 86400  { return "\(s / 3600)小时前" }
        return "\(s / 86400)天前"
    }

    // MARK: - View receipts (migration 024)

    /// True if the signed-in viewer owns the given story. Owners see
    /// the "看过" chip; non-owners silently record a view receipt.
    private func isOwner(of story: RemoteStory) -> Bool {
        guard let me = currentUserID else { return false }
        return story.owner_user_id == me
    }

    /// Called every time the active story changes (initial appear +
    /// each tap-through). Branches on ownership:
    ///
    ///   * Non-owner → fire-and-forget `recordView` (deduped via
    ///     `recordedViewIDs`). The insert is silent on failure; the
    ///     viewer never sees an error for a missed receipt.
    ///   * Owner    → lazy-load `viewerCount` for the chip. Cached in
    ///     `viewerCounts` so re-showing the story doesn't refetch.
    ///
    /// Split into two branches because the data flows are different:
    /// viewers never fetch, owners never insert.
    private func handleStoryBecameActive() {
        guard let story = currentStory else { return }
        if isOwner(of: story) {
            loadViewerCountIfNeeded(for: story.id)
        } else {
            recordViewIfNeeded(for: story.id)
        }
    }

    /// Records a non-owner view exactly once per story per session.
    /// The "viewing as" pet is the viewer's first pet — MVP scope,
    /// matches the rest of the app where the pet picker isn't
    /// exposed in the viewer. Skips silently if the viewer has no
    /// pets (onboarding gate makes this extremely rare, but the
    /// guard keeps the viewer crash-free for any historical edge
    /// case).
    private func recordViewIfNeeded(for storyID: UUID) {
        guard !recordedViewIDs.contains(storyID) else { return }
        guard let viewerPetID = petsService.pets.first?.id else { return }
        recordedViewIDs.insert(storyID)
        Task {
            try? await StoryService.shared.recordView(
                storyID: storyID,
                viewerPetID: viewerPetID
            )
        }
    }

    /// Lazy-loads the owner-only viewer count. Skips the round-trip
    /// if we've already cached a value for this story (owners who
    /// tap-through back and forth shouldn't re-fetch on every
    /// transition). Cache invalidates only when the viewer is re-
    /// presented — a story's view count in MVP only grows over its
    /// 24h lifetime, so a stale-by-a-few-seconds chip is acceptable.
    private func loadViewerCountIfNeeded(for storyID: UUID) {
        guard viewerCounts[storyID] == nil else { return }
        Task {
            let count = (try? await StoryService.shared.viewerCount(storyID: storyID)) ?? 0
            viewerCounts[storyID] = count
        }
    }

    // MARK: - Viewer chip

    /// Owner-only "看过" chip — white glass pill over the bottom of
    /// the canvas. Tappable; opens `StoryViewersSheet`.
    @ViewBuilder
    private func viewerCountChip(for story: RemoteStory) -> some View {
        let count = viewerCounts[story.id] ?? 0
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            activeViewerSheetStoryID = StoryIdentifier(id: story.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(count) 位看过")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.18), in: Capsule())
            .overlay(
                Capsule().stroke(Color.white.opacity(0.35), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Identifiable wrapper around a story id so `.sheet(item:)` can
/// drive `StoryViewersSheet`. SwiftUI's item-based sheet needs an
/// `Identifiable` binding; wrapping the raw UUID lets us avoid
/// declaring `UUID: Identifiable` globally (it's a common extension
/// footgun that can collide with other files).
private struct StoryIdentifier: Identifiable, Hashable {
    let id: UUID
}
