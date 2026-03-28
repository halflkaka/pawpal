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
    @State private var didSave = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Share a moment")
                        .font(.headline)
                    Text("Write a small pet update, like a simple 朋友圈 post.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if pets.isEmpty {
                Section {
                    Text("Add a pet first before posting.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Pet") {
                    Picker("Pet", selection: Binding(
                        get: { selectedPetID ?? pets.first?.id },
                        set: { selectedPetID = $0 }
                    )) {
                        ForEach(pets) { pet in
                            Text(pet.name.isEmpty ? "Unnamed Pet" : pet.name)
                                .tag(Optional(pet.id))
                        }
                    }
                }

                Section("Moment") {
                    TextField("What is your pet up to today?", text: $caption, axis: .vertical)
                        .lineLimit(5...10)
                }

                Section("Mood") {
                    TextField("Happy / Sleepy / Zoomies", text: $mood)
                }

                Section("Photos") {
                    PhotosPicker(selection: $selectedItems, maxSelectionCount: 9, matching: .images) {
                        Label("Choose Photos", systemImage: "photo.on.rectangle.angled")
                    }

                    if !selectedImageData.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(selectedImageData.enumerated()), id: \.offset) { _, data in
                                    if let uiImage = UIImage(data: data) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 84, height: 84)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section {
                    Button(didSave ? "Saved" : "Post") {
                        savePost()
                    }
                    .disabled(pets.isEmpty || caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || didSave)
                }
            }
        }
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
        didSave = true
    }
}
