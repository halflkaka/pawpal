import SwiftUI

struct ProfileView: View {
    let user: AppUser
    @Bindable var authManager: AuthManager
    @AppStorage("activePetID") private var activePetID = ""
    @StateObject private var petsService = PetsService()
    @State private var showingAddPet = false
    @State private var editingPet: RemotePet?
    @State private var isSavingPet = false
    @State private var pendingDeletePet: RemotePet?
    @State private var statusMessage: String?

    private var activePet: RemotePet? {
        if let match = petsService.pets.first(where: { $0.id.uuidString == activePetID }) {
            return match
        }
        return petsService.pets.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                sectionLabel("Pet")
                petHero
                petsSection

                sectionLabel("Account")
                accountSection
                signOutSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await petsService.loadPets(for: user.id)
            if activePetID.isEmpty, let firstPet = petsService.pets.first {
                activePetID = firstPet.id.uuidString
            }
        }
        .refreshable {
            await petsService.loadPets(for: user.id)
        }
        .sheet(isPresented: $showingAddPet) {
            ProfilePetEditorSheet(title: "Add Pet", pet: nil, isSaving: isSavingPet, errorMessage: petsService.errorMessage) { name, species, breed, age, weight, notes in
                guard !isSavingPet else { return false }
                isSavingPet = true
                defer { isSavingPet = false }

                let savedPet = await petsService.addPet(for: user.id, name: name, species: species, breed: breed, age: age, weight: weight, notes: notes)
                guard savedPet != nil else { return false }

                if let selected = petsService.pets.first(where: { $0.id.uuidString == activePetID }) {
                    activePetID = selected.id.uuidString
                } else if let firstPet = petsService.pets.first {
                    activePetID = firstPet.id.uuidString
                }

                return true
            }
        }
        .sheet(item: $editingPet) { pet in
            ProfilePetEditorSheet(title: "Edit Pet", pet: pet, isSaving: isSavingPet, errorMessage: petsService.errorMessage) { name, species, breed, age, weight, notes in
                guard !isSavingPet else { return false }
                isSavingPet = true
                defer { isSavingPet = false }

                var updatedPet = pet
                updatedPet.name = name
                updatedPet.species = species
                updatedPet.breed = breed
                updatedPet.age = age
                updatedPet.weight = weight
                updatedPet.notes = notes
                await petsService.updatePet(updatedPet, for: user.id)
                if petsService.errorMessage == nil {
                    statusMessage = "Pet updated"
                    return true
                }
                return false
            }
        }
        .alert("Delete Pet?", isPresented: deleteAlertBinding, presenting: pendingDeletePet) { pet in
            Button("Delete", role: .destructive) {
                Task {
                    let deletingActive = pet.id.uuidString == activePetID
                    await petsService.deletePet(pet.id, for: user.id)
                    if petsService.errorMessage == nil {
                        if deletingActive {
                            activePetID = petsService.pets.first?.id.uuidString ?? ""
                        }
                        statusMessage = "Pet deleted"
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeletePet = nil
            }
        } message: { pet in
            Text("Delete \(pet.name)? This can’t be undone.")
        }
    }

    private var petHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 76, height: 76)
                    .overlay {
                        Image(systemName: petIconName)
                            .font(.system(size: 28))
                            .foregroundStyle(.gray)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text(activePet?.name ?? "No Active Pet")
                        .font(.system(size: 24, weight: .semibold))
                    Text(activePetSummary)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if petsService.isLoading && petsService.pets.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading pets")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if let activePet {
                Button {
                    editingPet = activePet
                } label: {
                    HStack {
                        Text("Edit Pet")
                        Spacer()
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14))
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if !petsService.pets.isEmpty {
                Menu {
                    ForEach(petsService.pets) { pet in
                        Button(pet.name) {
                            activePetID = pet.id.uuidString
                            statusMessage = "Active pet updated"
                        }
                    }
                } label: {
                    HStack {
                        Text("Active Pet")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(activePet?.name ?? "Choose")
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 15))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if let statusMessage {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                    Text(statusMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if let errorMessage = petsService.errorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var petsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("My Pets")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("Add") {
                    showingAddPet = true
                }
                .font(.system(size: 15, weight: .medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if petsService.pets.isEmpty, petsService.isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading pets")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            } else if petsService.pets.isEmpty {
                HStack {
                    Text("No pets")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            } else {
                ForEach(Array(petsService.pets.enumerated()), id: \.element.id) { index, pet in
                    petRow(pet)

                    if index < petsService.pets.count - 1 {
                        Divider().padding(.leading, 84)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func petRow(_ pet: RemotePet) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: iconName(for: pet.species ?? ""))
                        .font(.system(size: 20))
                        .foregroundStyle(.gray)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(pet.name)
                        .font(.system(size: 16, weight: .medium))
                    if pet.id.uuidString == activePetID {
                        Text("Active")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.10))
                            .clipShape(Capsule())
                    }
                }

                if !petDetail(for: pet).isEmpty {
                    Text(petDetail(for: pet))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Menu {
                Button("Set Active") {
                    activePetID = pet.id.uuidString
                    statusMessage = "Active pet updated"
                }

                Button("Edit") {
                    editingPet = pet
                }

                Button("Delete", role: .destructive) {
                    pendingDeletePet = pet
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var accountSection: some View {
        VStack(spacing: 0) {
            accountRow(title: "Display Name", value: user.displayName ?? fallbackName)
            Divider().padding(.leading, 16)
            accountRow(title: "Email", value: user.email ?? "")
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var signOutSection: some View {
        Button {
            authManager.signOut()
        } label: {
            HStack {
                Text("Sign Out")
                    .foregroundStyle(.red)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletePet != nil },
            set: { newValue in
                if !newValue {
                    pendingDeletePet = nil
                }
            }
        )
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    private func accountRow(title: String, value: String) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 16))
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private var activePetSummary: String {
        guard let activePet else { return "Choose or create a pet" }
        let details = [activePet.species, activePet.breed, activePet.age]
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return details.isEmpty ? "Pet profile" : details.joined(separator: " · ")
    }

    private var petIconName: String {
        iconName(for: activePet?.species ?? "")
    }

    private func iconName(for species: String) -> String {
        switch species.lowercased() {
        case "cat": return "cat.fill"
        case "other": return "pawprint.circle.fill"
        default: return "dog.fill"
        }
    }

    private func petDetail(for pet: RemotePet) -> String {
        [pet.species, pet.breed, pet.age]
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var fallbackName: String {
        user.email?.components(separatedBy: "@").first ?? "User"
    }
}

private struct ProfilePetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var species: String
    @State private var breed: String
    @State private var age: String
    @State private var weight: String
    @State private var notes: String

    let title: String
    let isSaving: Bool
    let errorMessage: String?
    let onSave: (String, String, String, String, String, String) async -> Bool

    init(title: String, pet: RemotePet?, isSaving: Bool, errorMessage: String?, onSave: @escaping (String, String, String, String, String, String) async -> Bool) {
        self.title = title
        self.isSaving = isSaving
        self.errorMessage = errorMessage
        self.onSave = onSave
        _name = State(initialValue: pet?.name ?? "")
        _species = State(initialValue: pet?.species?.isEmpty == false ? pet?.species ?? "Dog" : "Dog")
        _breed = State(initialValue: pet?.breed ?? "")
        _age = State(initialValue: pet?.age ?? "")
        _weight = State(initialValue: pet?.weight ?? "")
        _notes = State(initialValue: pet?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                                .frame(width: 72, height: 72)
                                .overlay {
                                    Image(systemName: iconName(for: species))
                                        .font(.system(size: 28))
                                        .foregroundStyle(.gray)
                                }

                            Text(title)
                                .font(.system(size: 24, weight: .semibold))
                        }
                        .padding(.top, 20)

                        VStack(spacing: 0) {
                            inputRow(title: "Name") {
                                TextField("Pet name", text: $name)
                            }
                            Divider().padding(.leading, 16)
                            inputRow(title: "Species") {
                                Picker("Species", selection: $species) {
                                    Text("Dog").tag("Dog")
                                    Text("Cat").tag("Cat")
                                    Text("Other").tag("Other")
                                }
                                .pickerStyle(.menu)
                            }
                            Divider().padding(.leading, 16)
                            inputRow(title: "Breed") {
                                TextField("Optional", text: $breed)
                            }
                            Divider().padding(.leading, 16)
                            inputRow(title: "Age") {
                                TextField("Optional", text: $age)
                            }
                            Divider().padding(.leading, 16)
                            inputRow(title: "Weight") {
                                TextField("Optional", text: $weight)
                            }
                        }
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Notes")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)

                            TextField("Optional", text: $notes, axis: .vertical)
                                .lineLimit(4...8)
                                .font(.system(size: 16))
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        if let errorMessage {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundStyle(.red)
                                Text(errorMessage)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        Button {
                            Task {
                                let didSave = await onSave(name, species, breed, age, weight, notes)
                                if didSave {
                                    dismiss()
                                }
                            }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(canSave ? Color.green : Color(.tertiarySystemFill))
                                    .frame(height: 50)

                                if isSaving {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Save")
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundStyle(canSave ? .white : .secondary)
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .disabled(!canSave || isSaving)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func inputRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)

            content()
                .font(.system(size: 16))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private func iconName(for species: String) -> String {
        switch species.lowercased() {
        case "cat": return "cat.fill"
        case "other": return "pawprint.circle.fill"
        default: return "dog.fill"
        }
    }
}
