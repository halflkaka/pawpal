import PhotosUI
import SwiftUI
import SwiftData

struct CreatePostView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredPetProfile.createdAt, order: .reverse) private var pets: [StoredPetProfile]
    @AppStorage("activePetID") private var activePetID = ""

    @State private var selectedPetID: UUID?
    @State private var caption = ""
    @State private var mood = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImageData: [Data] = []
    @State private var didPost = false

    private var selectedPet: StoredPetProfile? {
        pets.first(where: { $0.id == selectedPetID })
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

                    if pets.isEmpty {
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
                }
                .padding(.bottom, 100)
            }
            .scrollIndicators(.hidden)

            if !pets.isEmpty {
                postButtonBar
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let activeID = UUID(uuidString: activePetID),
               pets.contains(where: { $0.id == activeID }) {
                selectedPetID = activeID
            } else {
                selectedPetID = pets.first?.id
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
                Text("New Post")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.primaryText)
                Text("Every post must feature one of your pets 🐾")
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
            Text("Add a pet first")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
            Text("Every post needs a pet. Head to your profile to add one.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 80)
    }

    // MARK: - Pet selector (required, prominent)

    private var petSelectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Posting as")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.secondaryText)
                // Required badge
                Text("required")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(PawPalTheme.orange.opacity(0.12), in: Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(pets) { pet in
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

    private func petChip(_ pet: StoredPetProfile) -> some View {
        let isSelected = selectedPetID == pet.id
        return Button {
            selectedPetID = pet.id
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? PawPalTheme.orange : PawPalTheme.cardSoft)
                        .frame(width: 38, height: 38)
                    Text(speciesEmoji(for: pet.species))
                        .font(.system(size: 18))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(pet.name.isEmpty ? "Unnamed" : pet.name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? .white : PawPalTheme.primaryText)
                    if !pet.species.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(pet.species)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isSelected ? .white.opacity(0.8) : PawPalTheme.tertiaryText)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? PawPalTheme.orange
                    : PawPalTheme.background,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? Color.clear : PawPalTheme.orangeGlow,
                        lineWidth: 1.5
                    )
            )
            .shadow(color: isSelected ? PawPalTheme.orange.opacity(0.3) : .clear, radius: 8, y: 4)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Text composer

    private var composerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Dynamic prompt based on selected pet
            let petName = selectedPet.map { $0.name.isEmpty ? "your pet" : $0.name } ?? "your pet"

            TextField("What's \(petName) up to today?", text: $caption, axis: .vertical)
                .lineLimit(6...14)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PawPalTheme.primaryText)

            Divider()
                .overlay(PawPalTheme.orangeGlow)

            HStack(spacing: 8) {
                Image(systemName: "face.smiling")
                    .foregroundStyle(PawPalTheme.orangeSoft)
                    .font(.system(size: 14))
                TextField("Add a mood tag (e.g. Zoomies, Nap Mode…)", text: $mood)
                    .font(.system(size: 13))
                    .foregroundStyle(PawPalTheme.secondaryText)
            }
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
                    Text("Photos")
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
                // Caption requirement hint
                if caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Add a caption to post")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PawPalTheme.tertiaryText)
                } else if selectedPetID == nil {
                    Text("Select a pet to post")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PawPalTheme.tertiaryText)
                } else {
                    Text("Ready to share!")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PawPalTheme.orange)
                }

                Spacer()

                Button {
                    savePost()
                } label: {
                    HStack(spacing: 8) {
                        Text(didPost ? "Posted! 🎉" : "Post")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        if !didPost {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 16))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(
                        canPost ? PawPalTheme.orange : PawPalTheme.tertiaryText.opacity(0.3),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .animation(.easeInOut(duration: 0.15), value: canPost)
                }
                .disabled(!canPost)
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
        case "dog":  return "🐶"
        case "cat":  return "🐱"
        case "rabbit", "bunny": return "🐰"
        case "bird": return "🦜"
        case "fish": return "🐟"
        case "hamster": return "🐹"
        default: return "🐾"
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

    private func savePost() {
        guard canPost,
              let pet = pets.first(where: { $0.id == selectedPetID }) ?? pets.first
        else { return }

        let post = StoredPost(
            petID: pet.id,
            petName: pet.name.isEmpty ? "Unnamed Pet" : pet.name,
            caption: caption,
            mood: mood,
            imageDataListJSON: StoredPost.encodeImageDataList(selectedImageData)
        )

        modelContext.insert(post)
        try? modelContext.save()

        activePetID = pet.id.uuidString

        // Reset form
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
