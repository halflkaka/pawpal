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
            VStack(alignment: .leading, spacing: 20) {
                introCard

                if pets.isEmpty {
                    emptyPetState
                } else {
                    composeCard
                    photoCard
                    postButton
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
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

    private var introCard: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color.orange.opacity(0.14))
                .frame(width: 54, height: 54)
                .overlay {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(.orange)
                }

            Text("New moment")
                .font(.system(size: 28, weight: .bold))

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.yellow.opacity(0.14), Color.orange.opacity(0.10), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var emptyPetState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a pet first")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var composeCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pet")
                    .font(.subheadline.weight(.semibold))

                Picker("Pet", selection: Binding(
                    get: { selectedPetID ?? pets.first?.id },
                    set: { selectedPetID = $0 }
                )) {
                    ForEach(pets) { pet in
                        Text(pet.name.isEmpty ? "Unnamed Pet" : pet.name)
                            .tag(Optional(pet.id))
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Caption")
                    .font(.subheadline.weight(.semibold))

                TextField("What is your pet doing today?", text: $caption, axis: .vertical)
                    .lineLimit(6...10)
                    .padding(16)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Mood")
                    .font(.subheadline.weight(.semibold))

                TextField("Happy, sleepy, playful...", text: $mood)
                    .padding(16)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var photoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Photos")
                    .font(.headline)
                Spacer()
                PhotosPicker(selection: $selectedItems, maxSelectionCount: 9, matching: .images) {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
            }

            if selectedImageData.isEmpty {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.04))
                    .frame(height: 150)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "photo")
                                .font(.system(size: 24))
                                .foregroundStyle(.secondary)
                            Text("Add photos")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(Array(selectedImageData.enumerated()), id: \.offset) { _, data in
                        if let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 140)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var postButton: some View {
        Button {
            savePost()
        } label: {
            HStack {
                Spacer()
                Text("Post")
                    .font(.headline)
                Spacer()
            }
            .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
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
