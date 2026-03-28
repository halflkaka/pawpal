import SwiftUI
import SwiftData

struct PetProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredPetProfile.name) private var storedPets: [StoredPetProfile]
    @AppStorage("selectedPetID") private var selectedPetID = ""
    @State private var showingAddPetSheet = false

    private var selectedPet: StoredPetProfile? {
        if let match = storedPets.first(where: { $0.id.uuidString == selectedPetID }) {
            return match
        }
        return storedPets.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topBar
                petListSection
                editorSection
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Pets")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddPetSheet) {
            AddPetSheet { name, species, breed, age, weight, notes in
                let pet = StoredPetProfile(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unnamed Pet" : name,
                    species: species,
                    breed: breed,
                    age: age,
                    weight: weight,
                    notes: notes
                )
                modelContext.insert(pet)
                try? modelContext.save()
                selectedPetID = pet.id.uuidString
            }
        }
        .task {
            if storedPets.isEmpty {
                let pet = StoredPetProfile(name: "Pet 1", species: "Dog", breed: "", age: "", weight: "", notes: "")
                modelContext.insert(pet)
                try? modelContext.save()
                selectedPetID = pet.id.uuidString
            } else if selectedPet == nil, let firstPet = storedPets.first {
                selectedPetID = firstPet.id.uuidString
            }
        }
    }

    private var topBar: some View {
        HStack {
            Text("Pet Profiles")
                .font(.title2.bold())
            Spacer()
            Button {
                showingAddPetSheet = true
            } label: {
                Label("Add Pet", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var petListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Pets")
                .font(.headline)

            ForEach(storedPets) { pet in
                Button {
                    selectedPetID = pet.id.uuidString
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: iconName(for: pet.species))
                            .font(.title3)
                            .frame(width: 38, height: 38)
                            .background(speciesColor(for: pet).opacity(0.14))
                            .foregroundStyle(speciesColor(for: pet))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayName(for: pet))
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(summaryLine(for: pet))
                                .font(.subheadline)
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
    private var editorSection: some View {
        if let pet = selectedPet {
            VStack(alignment: .leading, spacing: 14) {
                Text("Edit Selected Pet")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Name")
                    TextField("Pet name", text: binding(for: pet, keyPath: \.name))
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
                    TextField("Allergies, meds, chronic issues", text: binding(for: pet, keyPath: \.notes), axis: .vertical)
                        .lineLimit(4...8)
                        .textFieldStyle(.roundedBorder)

                    if storedPets.count > 1 {
                        Button(role: .destructive) {
                            delete(pet)
                        } label: {
                            Label("Delete This Pet", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(18)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private func delete(_ pet: StoredPetProfile) {
        let wasSelected = pet.id.uuidString == selectedPetID
        let nextSelectedID = storedPets.first(where: { $0.id != pet.id })?.id.uuidString ?? ""
        modelContext.delete(pet)
        try? modelContext.save()
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

    private func displayName(for pet: StoredPetProfile) -> String {
        let trimmed = pet.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unnamed Pet" : trimmed
    }

    private func iconName(for species: String) -> String {
        switch species.lowercased() {
        case "cat": return "cat.fill"
        case "other": return "pawprint.circle.fill"
        default: return "dog.fill"
        }
    }

    private func speciesColor(for pet: StoredPetProfile) -> Color {
        switch pet.species.lowercased() {
        case "cat": return .purple
        case "other": return .teal
        default: return .blue
        }
    }

    private func summaryLine(for pet: StoredPetProfile) -> String {
        let details = [pet.species, pet.breed, pet.age]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return details.isEmpty ? "Add breed and details" : details.joined(separator: " • ")
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
    }
}

private struct AddPetSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var species = "Dog"
    @State private var breed = ""
    @State private var age = ""
    @State private var weight = ""
    @State private var notes = ""

    let onSave: (String, String, String, String, String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("New Pet") {
                    TextField("Name", text: $name)
                    Picker("Species", selection: $species) {
                        Text("Dog").tag("Dog")
                        Text("Cat").tag("Cat")
                        Text("Other").tag("Other")
                    }
                    TextField("Breed", text: $breed)
                    TextField("Age", text: $age)
                    TextField("Weight", text: $weight)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Pet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, species, breed, age, weight, notes)
                        dismiss()
                    }
                }
            }
        }
    }
}
