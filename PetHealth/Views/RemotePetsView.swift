import SwiftUI

struct RemotePetsView: View {
    let user: AppUser
    @StateObject private var petsService = PetsService()
    @State private var showingAddPet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                if petsService.isLoading {
                    ProgressView()
                        .padding(.top, 120)
                } else if let errorMessage = petsService.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(.top, 80)
                        .padding(.horizontal, 24)
                } else if petsService.pets.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "pawprint.circle")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("No pets")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 120)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(petsService.pets.enumerated()), id: \.element.id) { index, pet in
                            petRow(pet)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)

                            if index < petsService.pets.count - 1 {
                                Divider()
                                    .padding(.leading, 80)
                            }
                        }
                    }
                    .background(Color(.systemBackground))
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Pets")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await petsService.loadPets(for: user.id)
        }
        .sheet(isPresented: $showingAddPet) {
            RemoteAddPetSheet { name, species, breed, sex, age, weight, bio, notes in
                Task {
                    await petsService.addPet(for: user.id, name: name, species: species, breed: breed, sex: sex, age: age, weight: weight, bio: bio, notes: notes)
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Text("Pets")
                .font(.system(size: 22, weight: .semibold))

            Spacer()

            Button {
                showingAddPet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        }
    }

    private func petRow(_ pet: RemotePet) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: iconName(for: pet.species ?? ""))
                        .font(.system(size: 18))
                        .foregroundStyle(.gray)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(pet.name)
                    .font(.system(size: 16, weight: .medium))

                let detail = [pet.species, pet.breed, pet.age]
                    .compactMap { $0 }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")

                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    private func iconName(for species: String) -> String {
        switch species.lowercased() {
        case "cat": return "cat.fill"
        case "other": return "pawprint.circle.fill"
        default: return "dog.fill"
        }
    }
}

private struct RemoteAddPetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var species = "Dog"
    @State private var breed = ""
    @State private var sex = ""
    @State private var age = ""
    @State private var weight = ""
    @State private var bio = ""
    @State private var notes = ""

    let onSave: (String, String, String, String, String, String, String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Species", selection: $species) {
                    Text("Dog").tag("Dog")
                    Text("Cat").tag("Cat")
                    Text("Other").tag("Other")
                }
                TextField("Breed", text: $breed)
                Picker("Sex", selection: $sex) {
                    Text("Not set").tag("")
                    Text("Male").tag("Male")
                    Text("Female").tag("Female")
                }
                TextField("Age", text: $age)
                TextField("Weight", text: $weight)
                TextField("Bio", text: $bio, axis: .vertical)
                    .lineLimit(2...4)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
            .navigationTitle("Add Pet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, species, breed, sex, age, weight, bio, notes)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
