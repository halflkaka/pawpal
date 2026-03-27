import SwiftUI
import SwiftData

struct PetProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredPetProfile.name) private var storedPets: [StoredPetProfile]
    @AppStorage("selectedPetID") private var selectedPetID = ""

    private var selectedPet: StoredPetProfile? {
        if let match = storedPets.first(where: { $0.id.uuidString == selectedPetID }) {
            return match
        }
        return storedPets.first
    }

    var body: some View {
        Form {
            petsSection
            profileSection
            tipsSection
        }
        .navigationTitle("Pet Profiles")
        .task {
            if storedPets.isEmpty {
                let pet = StoredPetProfile(name: "", species: "Dog", breed: "", age: "", weight: "", notes: "")
                modelContext.insert(pet)
                selectedPetID = pet.id.uuidString
            } else if selectedPet == nil, let firstPet = storedPets.first {
                selectedPetID = firstPet.id.uuidString
            }
        }
    }

    private var petsSection: some View {
        Section("Pets") {
            ForEach(storedPets) { pet in
                Button {
                    selectedPetID = pet.id.uuidString
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: iconName(for: pet.species))
                            .foregroundStyle(.blue)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(pet.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unnamed Pet" : pet.name)
                                .foregroundStyle(.primary)
                            Text(summaryLine(for: pet))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if pet.id.uuidString == selectedPetID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    if storedPets.count > 1 {
                        Button(role: .destructive) {
                            delete(pet)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            Button {
                addPet()
            } label: {
                Label("Add Another Pet", systemImage: "plus.circle.fill")
            }
        }
    }

    @ViewBuilder
    private var profileSection: some View {
        Section("Selected Pet") {
            if let pet = selectedPet {
                TextField("Name", text: binding(for: pet, keyPath: \.name))
                Picker("Species", selection: binding(for: pet, keyPath: \.species)) {
                    Text("Dog").tag("Dog")
                    Text("Cat").tag("Cat")
                    Text("Other").tag("Other")
                }
                TextField("Breed", text: binding(for: pet, keyPath: \.breed))
                TextField("Age", text: binding(for: pet, keyPath: \.age))
                TextField("Weight", text: binding(for: pet, keyPath: \.weight))
                TextField("Notes", text: binding(for: pet, keyPath: \.notes), axis: .vertical)
                    .lineLimit(3...6)
            } else {
                Text("No pet selected")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tipsSection: some View {
        Section("Tips") {
            Label("Keep one profile per pet so symptom checks and notes stay easier to scan.", systemImage: "lightbulb")
            Label("You can switch the active pet from the home screen before starting a check.", systemImage: "arrow.left.arrow.right.circle")
        }
        .foregroundStyle(.secondary)
    }

    private func addPet() {
        let pet = StoredPetProfile(name: "", species: "Dog", breed: "", age: "", weight: "", notes: "")
        modelContext.insert(pet)
        selectedPetID = pet.id.uuidString
    }

    private func delete(_ pet: StoredPetProfile) {
        let wasSelected = pet.id.uuidString == selectedPetID
        let nextSelectedID = storedPets.first(where: { $0.id != pet.id })?.id.uuidString ?? ""
        modelContext.delete(pet)

        if wasSelected {
            selectedPetID = nextSelectedID
        }
    }

    private func binding(for pet: StoredPetProfile, keyPath: ReferenceWritableKeyPath<StoredPetProfile, String>) -> Binding<String> {
        Binding(
            get: { pet[keyPath: keyPath] },
            set: { pet[keyPath: keyPath] = $0 }
        )
    }

    private func iconName(for species: String) -> String {
        switch species.lowercased() {
        case "cat": return "cat.fill"
        case "other": return "pawprint.circle.fill"
        default: return "dog.fill"
        }
    }

    private func summaryLine(for pet: StoredPetProfile) -> String {
        let details = [pet.species, pet.breed, pet.age]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return details.isEmpty ? "Add species, breed, and age" : details.joined(separator: " • ")
    }
}
