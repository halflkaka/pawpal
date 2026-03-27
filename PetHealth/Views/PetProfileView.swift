import SwiftUI
import SwiftData

struct PetProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredPetProfile.name) private var storedPets: [StoredPetProfile]
    @AppStorage("selectedPetID") private var selectedPetID = ""
    @State private var draftCounter = 1

    private var selectedPet: StoredPetProfile? {
        if let match = storedPets.first(where: { $0.id.uuidString == selectedPetID }) {
            return match
        }
        return storedPets.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                petsSection
                profileSection
                tipsSection
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Pet Profiles")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if storedPets.isEmpty {
                let pet = StoredPetProfile(name: "", species: "Dog", breed: "", age: "", weight: "", notes: "")
                modelContext.insert(pet)
                selectedPetID = pet.id.uuidString
            } else if selectedPet == nil, let firstPet = storedPets.first {
                selectedPetID = firstPet.id.uuidString
            }
            draftCounter = max(storedPets.count + 1, draftCounter)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Manage your pets")
                .font(.title2.bold())
            Text("Create one local profile per pet so symptom checks and saved history stay organized.")
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var petsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pets")
                    .font(.headline)
                Spacer()
                Button {
                    addPet()
                } label: {
                    Label("Add Pet", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }

            ForEach(storedPets) { pet in
                Button {
                    selectedPetID = pet.id.uuidString
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: iconName(for: pet.species))
                            .foregroundStyle(.blue)
                            .frame(width: 32, height: 32)
                            .background(Color.blue.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(pet.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unnamed Pet" : pet.name)
                                .foregroundStyle(.primary)
                                .font(.headline)
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
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        }
    }

    @ViewBuilder
    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Selected Pet")
                .font(.headline)

            if let pet = selectedPet {
                VStack(alignment: .leading, spacing: 14) {
                    fieldLabel("Name")
                    TextField("Name", text: binding(for: pet, keyPath: \.name))
                        .textFieldStyle(.roundedBorder)

                    fieldLabel("Species")
                    Picker("Species", selection: binding(for: pet, keyPath: \.species)) {
                        Text("Dog").tag("Dog")
                        Text("Cat").tag("Cat")
                        Text("Other").tag("Other")
                    }
                    .pickerStyle(.segmented)

                    fieldLabel("Breed")
                    TextField("Breed", text: binding(for: pet, keyPath: \.breed))
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("Age")
                            TextField("Age", text: binding(for: pet, keyPath: \.age))
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("Weight")
                            TextField("Weight", text: binding(for: pet, keyPath: \.weight))
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    fieldLabel("Notes")
                    TextField("Allergies, chronic issues, meds, quirks", text: binding(for: pet, keyPath: \.notes), axis: .vertical)
                        .lineLimit(3...6)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                Text("No pet selected")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tips")
                .font(.headline)
            Label("Tap Add Pet to create another local profile instantly.", systemImage: "plus.circle")
            Label("Swipe left on a pet to delete it.", systemImage: "hand.draw")
            Label("The selected pet is used for new symptom checks.", systemImage: "pawprint.fill")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func addPet() {
        let pet = StoredPetProfile(
            name: "Pet \(draftCounter)",
            species: "Dog",
            breed: "",
            age: "",
            weight: "",
            notes: ""
        )
        draftCounter += 1
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

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
    }
}
