import PhotosUI
import SwiftUI
import SwiftData

struct CreatePostView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredPetProfile.createdAt, order: .reverse) private var pets: [StoredPetProfile]

    @State private var selectedPetID: UUID?
    @State private var caption = ""
    @State private var mood = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImageData: [Data] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if pets.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "pawprint.circle")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("Add a pet first")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 120)
                } else {
                    VStack(spacing: 0) {
                        petSelectorRow
                        Divider().padding(.leading, 16)
                        textComposer
                        if !selectedImageData.isEmpty {
                            Divider().padding(.leading, 16)
                            imagePreviewSection
                        }
                    }
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    photoActionRow
                        .padding(.horizontal, 16)
                        .padding(.top, 14)

                    postButton
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if selectedPetID == nil {
                selectedPetID = pets.first?.id
            }
        }
        .onChange(of: selectedItems) { _, newItems in
            Task {
                await loadImages(from: newItems)
            }
        }
    }

    private var petSelectorRow: some View {
        HStack(spacing: 12) {
            Text("Pet")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            Spacer()

            Picker("Pet", selection: Binding(
                get: { selectedPetID ?? pets.first?.id },
                set: { selectedPetID = $0 }
            )) {
                ForEach(pets) { pet in
                    Text(pet.name.isEmpty ? "Unnamed Pet" : pet.name)
                        .tag(Optional(pet.id))
                }
            }
            .pickerStyle(.menu)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var textComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Share something...", text: $caption, axis: .vertical)
                .lineLimit(8...14)
                .font(.system(size: 17))

            TextField("Mood", text: $mood)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var imagePreviewSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(selectedImageData.enumerated()), id: \.offset) { _, data in
                    if let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 92, height: 92)
                            .clipped()
                    }
                }
            }
            .padding(16)
        }
    }

    private var photoActionRow: some View {
        HStack {
            PhotosPicker(selection: $selectedItems, maxSelectionCount: 9, matching: .images) {
                HStack(spacing: 8) {
                    Image(systemName: "photo")
                    Text("Photos")
                }
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            }

            Spacer()
        }
    }

    private var postButton: some View {
        Button {
            savePost()
        } label: {
            Text("Post")
                .font(.system(size: 17, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color(.tertiarySystemFill) : Color.green)
                .foregroundColor(caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .disabled(pets.isEmpty || caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        guard let pet = pets.first(where: { $0.id == selectedPetID }) ?? pets.first else { return }

        let post = StoredPost(
            petID: pet.id,
            petName: pet.name.isEmpty ? "Unnamed Pet" : pet.name,
            caption: caption,
            mood: mood,
            imageDataListJSON: StoredPost.encodeImageDataList(selectedImageData)
        )

        modelContext.insert(post)
        try? modelContext.save()

        caption = ""
        mood = ""
        selectedItems = []
        selectedImageData = []
    }
}
