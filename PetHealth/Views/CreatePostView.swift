import SwiftUI
import SwiftData

struct CreatePostView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredPetProfile.createdAt, order: .reverse) private var pets: [StoredPetProfile]

    @State private var selectedPetID: UUID?
    @State private var caption = ""
    @State private var mood = ""
    @State private var didSave = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Share a moment")
                        .font(.headline)
                    Text("Write a small update like a pet朋友圈 post.")
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
            mood: mood
        )

        modelContext.insert(post)
        try? modelContext.save()
        didSave = true
    }
}
