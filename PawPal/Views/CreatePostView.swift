import PhotosUI
import SwiftUI
import UIKit

struct CreatePostView: View {
    @Bindable var authManager: AuthManager
    @AppStorage("activePetID") private var activePetID = ""

    @StateObject private var petsService   = PetsService()
    @StateObject private var postsService  = PostsService()
    @StateObject private var followService = FollowService()

    @State private var selectedPetID: UUID?
    @State private var caption = ""
    @State private var mood = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImageData: [Data] = []
    @State private var didPost = false
    @State private var showingPetPicker = false
    @State private var photoCarouselIndex = 0

    let onPostPublished: (() -> Void)?

    /// Pre-seeded caption from a milestone / memory tap. When non-nil and
    /// `caption` is still empty at `.task` time, this is copied in so the
    /// composer opens with the prompt already drafted.
    ///
    /// NOTE: Declared without a `= nil` default at the property level
    /// because Swift's synthesized memberwise init does not honour
    /// SE-0242 defaults reliably when the surrounding property list is
    /// dominated by property wrappers (@Bindable, @StateObject,
    /// @AppStorage, @State above). The explicit init below carries the
    /// defaults instead, which keeps `MainTabView`'s 2-arg call site
    /// (`CreatePostView(authManager:) { ... }`) compiling while letting
    /// the milestone tap sites pass all four named args.
    let prefillCaption: String?

    /// Pre-selected pet from a milestone / memory tap. Takes precedence
    /// over the persisted `activePetID` so tapping a milestone for Pet A
    /// doesn't accidentally open the composer on Pet B because B was the
    /// most recently composed-for pet. See note on `prefillCaption`
    /// above for why the default lives on the explicit init, not here.
    let prefillPetID: UUID?

    /// Explicit init so the prefill properties get reachable defaults.
    /// See the note on `prefillCaption` for the SE-0242 quirk that
    /// motivates this. All four parameters are named; the tab-bar call
    /// site uses the trailing-closure form for `onPostPublished` and
    /// relies on the prefill defaults to fill in nil.
    init(
        authManager: AuthManager,
        onPostPublished: (() -> Void)? = nil,
        prefillCaption: String? = nil,
        prefillPetID: UUID? = nil
    ) {
        self._authManager = Bindable(authManager)
        self.onPostPublished = onPostPublished
        self.prefillCaption = prefillCaption
        self.prefillPetID = prefillPetID
    }

    /// Pet-first mood chips — subject is the pet, not the user. Single-select.
    private let moodChips: [MoodChip] = [
        MoodChip(emoji: "😋", label: "正在吃饭"),
        MoodChip(emoji: "🐾", label: "散步中"),
        MoodChip(emoji: "🥱", label: "犯困了"),
        MoodChip(emoji: "🎾", label: "玩耍中"),
        MoodChip(emoji: "🛁", label: "洗澡中"),
        MoodChip(emoji: "🥰", label: "撒娇中"),
        MoodChip(emoji: "🧸", label: "发呆中")
    ]

    private var selectedPet: RemotePet? {
        petsService.pets.first(where: { $0.id == selectedPetID })
    }

    private var canPost: Bool {
        selectedPetID != nil && !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            PawPalBackground().ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    customHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    if petsService.isLoading {
                        ProgressView()
                            .padding(.top, 80)
                    } else if petsService.pets.isEmpty {
                        noPetsPrompt
                    } else {
                        petHeroCard
                        photoCard
                        captionCard
                        moodRow

                        if let error = postsService.errorMessage {
                            Text(error)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 4)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)

            if !petsService.pets.isEmpty {
                submitBar
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let user = authManager.currentUser {
                async let pets: () = petsService.loadPets(for: user.id)
                async let follows: () = followService.loadFollowing(for: user.id)
                _ = await (pets, follows)
            }
            // Prefill precedence: explicit milestone/memory pet → persisted
            // activePetID → first available. A milestone tap for Pet A must
            // land on Pet A even if the user last composed for Pet B.
            if let prefill = prefillPetID,
               petsService.pets.contains(where: { $0.id == prefill }) {
                selectedPetID = prefill
            } else if let activeID = UUID(uuidString: activePetID),
                      petsService.pets.contains(where: { $0.id == activeID }) {
                selectedPetID = activeID
            } else {
                selectedPetID = petsService.pets.first?.id
            }

            // Seed the caption from the milestone / memory prompt if the
            // user hasn't typed anything yet. Guarded on `caption.isEmpty`
            // so a second open with the same prefill (unlikely, but
            // possible via rapid tap → dismiss → re-tap) doesn't stomp
            // the user's in-progress edits.
            if caption.isEmpty, let prefillCaption, !prefillCaption.isEmpty {
                caption = prefillCaption
            }
        }
        .onChange(of: selectedItems) { _, newItems in
            Task { await loadImages(from: newItems) }
        }
        .onChange(of: selectedPetID) { _, newValue in
            if let newValue { activePetID = newValue.uuidString }
        }
        .sheet(isPresented: $showingPetPicker) {
            petPickerSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var customHeader: some View {
        HStack(alignment: .center) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onPostPublished?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(PawPalTheme.secondaryText)
                    .frame(width: 36, height: 36)
                    .background(PawPalTheme.card, in: Circle())
                    .shadow(color: PawPalTheme.softShadow, radius: 6, y: 2)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("分享毛孩子的今日")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await savePost() }
            } label: {
                Text(postsService.isPosting ? "发布中" : "发布")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(
                        canPost && !postsService.isPosting
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [PawPalTheme.orange, PawPalTheme.orangeSoft],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                              )
                            : AnyShapeStyle(PawPalTheme.tertiaryText.opacity(0.3)),
                        in: Capsule()
                    )
                    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: canPost)
            }
            .buttonStyle(.plain)
            .disabled(!canPost || postsService.isPosting)
        }
    }

    // MARK: - No pets state

    private var noPetsPrompt: some View {
        VStack(spacing: 16) {
            Text("🐾")
                .font(.system(size: 52))
            Text("先添加你的毛孩子吧")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
            Text("在个人主页添加一只，就能开始记录 TA 的每一个精彩瞬间。")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Text("添加后随时回来分享 TA 的日常")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PawPalTheme.tertiaryText)
        }
        .padding(.top, 80)
    }

    // MARK: - Pet hero card (MOST prominent — pet is the protagonist)

    private var petHeroCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showingPetPicker = true
        } label: {
            HStack(spacing: 14) {
                petAvatar(for: selectedPet, size: 56)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(selectedPet?.name ?? "选一只毛孩子")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(PawPalTheme.primaryText)
                        Text("今日想说")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(PawPalTheme.orange)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(PawPalTheme.orange.opacity(0.12), in: Capsule())
                    }

                    if let pet = selectedPet {
                        speciesBreedChip(for: pet)
                    } else {
                        Text("点击选择发布身份")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(PawPalTheme.tertiaryText)
                    }
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PawPalTheme.tertiaryText)
            }
            .padding(18)
            .background(PawPalTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(PawPalTheme.orangeGlow.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: PawPalTheme.softShadow, radius: 12, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func speciesBreedChip(for pet: RemotePet) -> some View {
        let species = pet.species.map { speciesDisplayName($0) } ?? ""
        let breed = pet.breed?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parts = [species, breed].filter { !$0.isEmpty }
        let label = parts.isEmpty ? "毛孩子" : parts.joined(separator: " · ")

        return HStack(spacing: 4) {
            Text(speciesEmoji(for: pet.species ?? ""))
                .font(.system(size: 11))
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(PawPalTheme.secondaryText)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(PawPalTheme.cardSoft, in: Capsule())
    }

    private func petAvatar(for pet: RemotePet?, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(PawPalTheme.cardSoft)
                .frame(width: size, height: size)

            if let pet, let urlStr = pet.avatar_url, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    } else {
                        Text(speciesEmoji(for: pet.species ?? ""))
                            .font(.system(size: size * 0.46))
                    }
                }
            } else if let pet {
                Text(speciesEmoji(for: pet.species ?? ""))
                    .font(.system(size: size * 0.46))
            } else {
                Text("🐾")
                    .font(.system(size: size * 0.46))
            }
        }
        .overlay(
            Circle().stroke(PawPalTheme.orangeGlow, lineWidth: 2)
        )
    }

    // MARK: - Pet picker sheet

    private var petPickerSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("选择发布身份")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.primaryText)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(petsService.pets) { pet in
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                                selectedPetID = pet.id
                            }
                            showingPetPicker = false
                        } label: {
                            HStack(spacing: 14) {
                                petAvatar(for: pet, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pet.name)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(PawPalTheme.primaryText)
                                    if let species = pet.species, !species.isEmpty {
                                        Text(speciesDisplayName(species))
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(PawPalTheme.tertiaryText)
                                    }
                                }
                                Spacer()
                                if pet.id == selectedPetID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(PawPalTheme.orange)
                                }
                            }
                            .padding(14)
                            .background(
                                pet.id == selectedPetID
                                    ? PawPalTheme.orange.opacity(0.08)
                                    : PawPalTheme.card,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(
                                        pet.id == selectedPetID
                                            ? PawPalTheme.orange
                                            : PawPalTheme.hairline,
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .background(PawPalTheme.background.ignoresSafeArea())
    }

    // MARK: - Photo card

    private var photoCard: some View {
        Group {
            if selectedImageData.isEmpty {
                PhotosPicker(selection: $selectedItems, maxSelectionCount: 9, matching: .images) {
                    VStack(spacing: 10) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(PawPalTheme.orange)
                            .frame(width: 64, height: 64)
                            .background(PawPalTheme.orange.opacity(0.12), in: Circle())
                        Text("添加一张照片")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(PawPalTheme.primaryText)
                        Text("让大家看看 TA 今天的样子")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(PawPalTheme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .background(PawPalTheme.cardSoft, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                PawPalTheme.orangeGlow,
                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                            )
                    )
                }
                .buttonStyle(.plain)
            } else {
                photoCarousel
            }
        }
    }

    private var photoCarousel: some View {
        VStack(spacing: 10) {
            TabView(selection: $photoCarouselIndex) {
                ForEach(Array(selectedImageData.enumerated()), id: \.offset) { index, data in
                    ZStack(alignment: .topTrailing) {
                        if let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 260)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                                selectedImageData.remove(at: index)
                                if selectedItems.indices.contains(index) {
                                    selectedItems.remove(at: index)
                                }
                                photoCarouselIndex = min(photoCarouselIndex, max(0, selectedImageData.count - 1))
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.black.opacity(0.45), in: Circle())
                        }
                        .padding(10)
                        .buttonStyle(.plain)
                    }
                    .tag(index)
                }
            }
            .frame(height: 260)
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 12) {
                if selectedImageData.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<selectedImageData.count, id: \.self) { i in
                            Circle()
                                .fill(
                                    i == photoCarouselIndex
                                        ? PawPalTheme.orange
                                        : PawPalTheme.tertiaryText.opacity(0.3)
                                )
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                Spacer()
                PhotosPicker(selection: $selectedItems, maxSelectionCount: 9, matching: .images) {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 12, weight: .bold))
                        Text("替换照片")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(PawPalTheme.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(PawPalTheme.orange.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Caption card

    private var captionCard: some View {
        let petName = selectedPet?.name ?? "TA"
        let placeholder = "说点 \(petName) 今天的故事吧…"

        return ZStack(alignment: .topLeading) {
            if caption.isEmpty {
                Text(placeholder)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PawPalTheme.tertiaryText)
                    .padding(.top, 2)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }

            TextField("", text: $caption, axis: .vertical)
                .lineLimit(4...10)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PawPalTheme.primaryText)
                .tint(PawPalTheme.orange)
        }
        .padding(16)
        .background(PawPalTheme.cardSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PawPalTheme.hairline, lineWidth: 0.5)
        )
    }

    // MARK: - Mood chips row

    private var moodRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TA 现在的状态")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.secondaryText)
                .padding(.leading, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(moodChips) { chip in
                        moodChipButton(chip)
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
            }
        }
    }

    private func moodChipButton(_ chip: MoodChip) -> some View {
        let value = "\(chip.emoji) \(chip.label)"
        let isSelected = mood == value
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                mood = isSelected ? "" : value
            }
        } label: {
            HStack(spacing: 6) {
                Text(chip.emoji)
                    .font(.system(size: 15))
                Text(chip.label)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : PawPalTheme.secondaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                isSelected ? PawPalTheme.orange : PawPalTheme.card,
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? Color.clear : PawPalTheme.hairline,
                        lineWidth: 0.5
                    )
            )
            .shadow(
                color: isSelected ? PawPalTheme.orange.opacity(0.3) : PawPalTheme.softShadow,
                radius: isSelected ? 8 : 3,
                y: 1
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Submit bar (gradient)

    private var submitBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await savePost() }
                } label: {
                    HStack(spacing: 8) {
                        if postsService.isPosting {
                            ProgressView().tint(.white)
                        } else if didPost {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 15, weight: .bold))
                        }
                        Text(didPost ? "已发布！🎉" : (postsService.isPosting ? "发布中…" : "发布这条动态"))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        canPost && !postsService.isPosting
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [PawPalTheme.orange, PawPalTheme.orangeSoft],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                              )
                            : AnyShapeStyle(PawPalTheme.tertiaryText.opacity(0.3)),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .shadow(
                        color: canPost ? PawPalTheme.orange.opacity(0.4) : .clear,
                        radius: 14, y: 6
                    )
                    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: canPost)
                }
                .disabled(!canPost || postsService.isPosting)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 18)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Helpers

    private struct MoodChip: Identifiable {
        let id = UUID()
        let emoji: String
        let label: String
    }

    private func speciesEmoji(for species: String) -> String {
        switch species.lowercased() {
        case "dog":            return "🐶"
        case "cat":            return "🐱"
        case "rabbit", "bunny": return "🐰"
        case "bird":           return "🦜"
        case "fish":           return "🐟"
        case "hamster":        return "🐹"
        default:               return "🐾"
        }
    }

    private func loadImages(from items: [PhotosPickerItem]) async {
        var loaded: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                loaded.append(data)
            }
        }
        selectedImageData = loaded
        photoCarouselIndex = 0
    }

    private func speciesDisplayName(_ english: String) -> String {
        switch english.lowercased() {
        case "dog": return "狗狗"
        case "cat": return "猫咪"
        case "rabbit", "bunny": return "兔兔"
        case "bird": return "鸟类"
        case "fish": return "鱼类"
        case "hamster": return "仓鼠"
        default: return english
        }
    }

    private func savePost() async {
        guard canPost, let pet = selectedPet, let user = authManager.currentUser else { return }

        let followingIDs = followService.followingIDs.isEmpty
            ? nil
            : followService.feedFilter(includingSelf: user.id)

        let success = await postsService.createPost(
            userID: user.id,
            petID: pet.id,
            caption: caption,
            mood: mood,
            imageData: selectedImageData,
            followingIDs: followingIDs
        )

        if success {
            activePetID = pet.id.uuidString
            caption = ""
            mood = ""
            selectedItems = []
            selectedImageData = []
            photoCarouselIndex = 0
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { didPost = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                onPostPublished?()
                withAnimation { didPost = false }
            }
        }
    }
}
