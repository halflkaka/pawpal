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
                heroCard
                petSwitcherSection
                profileEditorSection
                careSnapshotSection
                notesSection
                tipsSection
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Pet Profiles")
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

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your pets, organized")
                        .font(.title2.bold())
                    Text("Keep each profile local on this device so checks, notes, and history stay lightweight and easy to revisit.")
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button {
                    addPet()
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                metricPill(title: "Pets", value: "\(storedPets.count)", tint: .white.opacity(0.24))
                metricPill(title: "Selected", value: selectedPetName, tint: .white.opacity(0.20))
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.indigo, Color.blue, Color.teal],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var petSwitcherSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Pet Cards")
                    .font(.headline)
                Spacer()
                Text("Tap to edit")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(storedPets) { pet in
                        Button {
                            selectedPetID = pet.id.uuidString
                        } label: {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(speciesColor(for: pet).opacity(0.16))
                                            .frame(width: 46, height: 46)
                                        Image(systemName: iconName(for: pet.species))
                                            .font(.title3)
                                            .foregroundStyle(speciesColor(for: pet))
                                    }
                                    Spacer()
                                    if pet.id.uuidString == selectedPetID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(displayName(for: pet))
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(summaryLine(for: pet))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                Text(weightOrPrompt(for: pet))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(speciesColor(for: pet))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(speciesColor(for: pet).opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .padding(18)
                            .frame(width: 220, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(pet.id.uuidString == selectedPetID ? Color.blue.opacity(0.45) : Color.clear, lineWidth: 2)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
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
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private var profileEditorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Profile")
                .font(.headline)

            if let pet = selectedPet {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        statCard(title: "Species", value: pet.species.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown" : pet.species, tint: speciesColor(for: pet))
                        statCard(title: "Age", value: pet.age.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add age" : pet.age, tint: .orange)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Name")
                        TextField("Mochi", text: binding(for: pet, keyPath: \.name))
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Species")
                        Picker("Species", selection: binding(for: pet, keyPath: \.species)) {
                            Text("Dog").tag("Dog")
                            Text("Cat").tag("Cat")
                            Text("Other").tag("Other")
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Breed")
                        TextField("Breed or mix", text: binding(for: pet, keyPath: \.breed))
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("Age")
                            TextField("3 years", text: binding(for: pet, keyPath: \.age))
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("Weight")
                            TextField("18 lb", text: binding(for: pet, keyPath: \.weight))
                                .textFieldStyle(.roundedBorder)
                        }
                    }

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
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var careSnapshotSection: some View {
        if let pet = selectedPet {
            VStack(alignment: .leading, spacing: 14) {
                Text("Care Snapshot")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 12) {
                    snapshotRow(title: "Profile completeness", value: completionText(for: pet), systemImage: "checkmark.seal.fill", tint: .green)
                    snapshotRow(title: "Best for checks", value: readinessText(for: pet), systemImage: "stethoscope", tint: .blue)
                    snapshotRow(title: "Local privacy", value: "Saved only on this device", systemImage: "lock.fill", tint: .purple)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        if let pet = selectedPet {
            VStack(alignment: .leading, spacing: 14) {
                Text("Health Notes")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Allergies, meds, chronic issues, food notes, behavior quirks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Chicken allergy, takes joint supplement, hates nail trims…", text: binding(for: pet, keyPath: \.notes), axis: .vertical)
                        .lineLimit(5...9)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Why this layout is better")
                .font(.headline)
            Label("Pet cards make switching pets faster than a plain list.", systemImage: "square.grid.2x2.fill")
            Label("The selected profile stays in one focused editor instead of a crowded stack.", systemImage: "slider.horizontal.3")
            Label("Everything remains local and lightweight — no account setup, no cloud sync.", systemImage: "internaldrive.fill")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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

    private var selectedPetName: String {
        guard let selectedPet else { return "None" }
        return displayName(for: selectedPet)
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
        return details.isEmpty ? "Add species, breed, and age" : details.joined(separator: " • ")
    }

    private func weightOrPrompt(for pet: StoredPetProfile) -> String {
        let weight = pet.weight.trimmingCharacters(in: .whitespacesAndNewlines)
        return weight.isEmpty ? "Add weight" : weight
    }

    private func completionText(for pet: StoredPetProfile) -> String {
        let fields = [pet.name, pet.species, pet.breed, pet.age, pet.weight, pet.notes]
        let complete = fields.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        return "\(complete)/6 fields filled"
    }

    private func readinessText(for pet: StoredPetProfile) -> String {
        let hasBasics = !pet.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !pet.species.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !pet.age.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return hasBasics ? "Profile is ready for more useful symptom context" : "Add name, species, and age for better context"
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
    }

    private func metricPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.82))
            Text(value)
                .font(.headline)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func snapshotRow(title: String, value: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}
