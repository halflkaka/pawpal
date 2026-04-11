import PhotosUI
import SwiftUI

struct CreatePostView: View {
    @Bindable var authManager: AuthManager
    @AppStorage("activePetID") private var activePetID = ""

    @StateObject private var petsService  = PetsService()
    @StateObject private var postsService = PostsService()

    @State private var selectedPetID: UUID?
    @State private var caption = ""
    @State private var mood = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImageData: [Data] = []
    @State private var didPost = false

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
                VStack(spacing: 0) {
                    customHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 20)

                    if petsService.isLoading {
                        ProgressView()
                            .padding(.top, 80)
                    } else if petsService.pets.isEmpty {
                        noPetsPrompt
                    } else {
                        VStack(spacing: 16) {
                            petSelectorSection
                            composerSection
                            if !selectedImageData.isEmpty {
                                imagePreviewSection
                            }
                            mediaActionsRow
                        }
                        .padding(.horizontal, 16)
                    }

                    if let error = postsService.errorMessage {
                        Text(error)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }
                }
                .padding(.bottom, 100)
            }
            .scrollIndicators(.hidden)

            if !petsService.pets.isEmpty {
                postButtonBar
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let user = authManager.currentUser {
                await petsService.loadPets(for: user.id)
            }
            if let activeID = UUID(uuidString: activePetID),
               petsService.pets.contains(where: { $0.id == activeID }) {
                selectedPetID = activeID
            } else {
                selectedPetID = petsService.pets.first?.id
            }
        }
        .onChange(of: selectedItems) { _, newItems in
            Task { await loadImages(from: newItems) }
        }
        .onChange(of: selectedPetID) { _, newValue in
            if let newValue { activePetID = newValue.uuidString }
        }
    }

    // MARK: - Header

    private var customHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("发布动态")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.primaryText)
                Text("每条动态都需要关联一只你的宠物 🐾")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(PawPalTheme.tertiaryText)
            }
            Spacer()
        }
    }

    // MARK: - No pets state

    private var noPetsPrompt: some View {
        VStack(spacing: 16) {
            Text("🐾")
                .font(.system(size: 52))
            Text("请先添加宠物")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
            Text("每条动态都需要宠物，先去个人主页添加一只吧。")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 80)
    }

    // MARK: - Pet selector

    private var petSelectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("发布身份")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.secondaryText)
                Text("必选")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(PawPalTheme.orange.opacity(0.12), in: Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(petsService.pets) { pet in
                        petChip(pet)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .background(PawPalTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: PawPalTheme.softShadow, radius: 12, y: 4)
    }

    private func petChip(_ pet: RemotePet) -> some View {
        let isSelected = selectedPetID == pet.id
        return Button {
            selectedPetID = pet.id
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? PawPalTheme.orange : PawPalTheme.cardSoft)
                        .frame(width: 38, height: 38)
                    Text(speciesEmoji(for: pet.species ?? ""))
                        .font(.system(size: 18))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(pet.name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? .white : PawPalTheme.primaryText)
                    if let species = pet.species, !species.isEmpty {
                        Text(speciesDisplayName(species))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isSelected ? .white.opacity(0.8) : PawPalTheme.tertiaryText)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected ? PawPalTheme.orange : PawPalTheme.background,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.clear : PawPalTheme.orangeGlow, lineWidth: 1.5)
            )
            .shadow(color: isSelected ? PawPalTheme.orange.opacity(0.3) : .clear, radius: 8, y: 4)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mood emoji picker

    private var moodEmojiPicker: some View {
        let moodEmojis = ["😊", "😍", "🤔", "😴", "🤩", "😻", "🥰", "🎉"]
        return VStack(alignment: .leading, spacing: 10) {
            Text("心情标签")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.secondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(moodEmojis, id: \.self) { emoji in
                        Button {
                            mood = emoji == mood ? "" : emoji
                        } label: {
                            Text(emoji)
                                .font(.system(size: 22))
                                .frame(width: 44, height: 44)
                                .background(
                                    mood == emoji ? PawPalTheme.orange.opacity(0.2) : Color.clear,
                                    in: Circle()
                                )
                                .overlay(
                                    Circle().stroke(
                                        mood == emoji ? PawPalTheme.orange : Color.clear,
                                        lineWidth: 2
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Text composer

    private var composerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let petName = selectedPet.map { $0.name } ?? "你的宠物"

            TextField("今天想分享一下 \(petName) 的什么瞬间？", text: $caption, axis: .vertical)
                .lineLimit(6...14)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PawPalTheme.primaryText)

            Divider()
                .overlay(PawPalTheme.orangeGlow)

            moodEmojiPicker
        }
        .padding(16)
        .background(PawPalTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: PawPalTheme.softShadow, radius: 12, y: 4)
    }

    // MARK: - Image preview

    private var imagePreviewSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(selectedImageData.enumerated()), id: \.offset) { index, data in
                    if let uiImage = UIImage(data: data) {
                        ZStack(alignment: .topLeading) {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                                Button {
                                    selectedImageData.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.white)
                                        .background(Color.black.opacity(0.4), in: Circle())
                                }
                                .offset(x: 6, y: -6)
                            }

                            Text("\(index + 1)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(PawPalTheme.orange, in: Circle())
                                .offset(x: -6, y: -6)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .padding(16)
        .background(PawPalTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: PawPalTheme.softShadow, radius: 12, y: 4)
    }

    // MARK: - Media actions

    private var mediaActionsRow: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $selectedItems, maxSelectionCount: 9, matching: .images) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 14, weight: .semibold))
                    Text("照片")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundStyle(PawPalTheme.secondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(PawPalTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: PawPalTheme.softShadow, radius: 8, y: 3)
            }
            Spacer()
        }
    }

    // MARK: - Post button bar

    private var postButtonBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.1)
            HStack(spacing: 16) {
                if postsService.isPosting {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("发布中…")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(PawPalTheme.secondaryText)
                    }
                } else if caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("先写点内容才能发布")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PawPalTheme.tertiaryText)
                } else if selectedPetID == nil {
                    Text("请选择一只宠物再发布")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PawPalTheme.tertiaryText)
                } else {
                    Text("可以发布啦！")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PawPalTheme.orange)
                }

                Spacer()

                Button {
                    Task { await savePost() }
                } label: {
                    HStack(spacing: 8) {
                        Text(didPost ? "已发布！🎉" : "发布")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        if !didPost && !postsService.isPosting {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 16))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(
                        canPost && !postsService.isPosting
                            ? PawPalTheme.orange
                            : PawPalTheme.tertiaryText.opacity(0.3),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .animation(.easeInOut(duration: 0.15), value: canPost)
                }
                .disabled(!canPost || postsService.isPosting)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Helpers

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

        let success = await postsService.createPost(
            userID: user.id,
            petID: pet.id,
            caption: caption,
            mood: mood,
            imageData: selectedImageData
        )

        if success {
            activePetID = pet.id.uuidString
            caption = ""
            mood = ""
            selectedItems = []
            selectedImageData = []
            withAnimation { didPost = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { didPost = false }
            }
        }
    }
}
