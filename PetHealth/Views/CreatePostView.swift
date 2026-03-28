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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                formCard
                saveButton
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("New Post")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if selectedPetID == nil {
                selectedPetID = pets.first?.id
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Share a pet moment")
                .font(.title2.bold())
            Text("Keep it simple for now: pick a pet, add a caption, and save locally.")
                .foregroundStyle(.secondary)
        }
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if pets.isEmpty {
                Text("Add a pet first before creating a post.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Pet")
                    .font(.headline)

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

                Text("Caption")
                    .font(.headline)
                TextField("Today Mochi finally sat still for a photo…", text: $caption, axis: .vertical)
                    .lineLimit(4...8)
                    .textFieldStyle(.roundedBorder)

                Text("Mood")
                    .font(.headline)
                TextField("Happy / Sleepy / Zoomies", text: $mood)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var saveButton: some View {
        Button {
            savePost()
        } label: {
            HStack {
                Spacer()
                Text(didSave ? "Saved" : "Save Post")
                    .font(.headline)
                Spacer()
            }
            .padding()
        }
        .buttonStyle(.borderedProminent)
        .disabled(pets.isEmpty || caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || didSave)
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
