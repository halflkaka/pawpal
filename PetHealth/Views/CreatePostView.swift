import SwiftUI
import SwiftData

struct CreatePostView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredPetProfile.createdAt, order: .reverse) private var pets: [StoredPetProfile]

    @State private var selectedPetID: UUID?
    @State private var caption = ""
    @State private var mood = ""
    @State private var imageSlotCount = 0
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
                    Stepper(value: $imageSlotCount, in: 0...9) {
                        Text(imageSlotCount == 0 ? "No photo slots" : "\(imageSlotCount) photo slot\(imageSlotCount == 1 ? "" : "s")")
                    }
                    Text("Placeholder for local photo support.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
    }

    private func savePost() {
        guard let pet = pets.first(where: { $0.id == selectedPetID }) ?? pets.first else { return }

        let post = StoredPost(
            petID: pet.id,
            petName: pet.name.isEmpty ? "Unnamed Pet" : pet.name,
            caption: caption,
            mood: mood,
            imageSlotCount: imageSlotCount
        )

        modelContext.insert(post)
        try? modelContext.save()
        didSave = true
    }
}
