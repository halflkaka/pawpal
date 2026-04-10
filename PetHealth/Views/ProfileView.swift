import SwiftUI

struct ProfileView: View {
    let user: AppUser
    @Bindable var authManager: AuthManager
    @AppStorage("activePetID") private var activePetID = ""
    @StateObject private var petsService = PetsService()
    @State private var showingAddPet = false
    @State private var editingPet: RemotePet?
    @State private var showingEditAccount = false
    @State private var isSavingPet = false
    @State private var isSavingProfile = false
    @State private var pendingDeletePet: RemotePet?
    @State private var statusMessage: String?
    @State private var profile: RemoteProfile?
    @State private var isLoadingProfile = false
    @State private var profileErrorMessage: String?

    private let profileService = ProfileService()

    private var activePet: RemotePet? {
        if let match = petsService.pets.first(where: { $0.id.uuidString == activePetID }) {
            return match
        }
        return petsService.pets.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                petHero
                petsSection
                petDetailsSection
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
            await loadProfile()
            await petsService.loadPets(for: user.id)
            if activePetID.isEmpty, let firstPet = petsService.pets.first {
                activePetID = firstPet.id.uuidString
            }
        }
        .refreshable {
            await loadProfile()
            await petsService.loadPets(for: user.id)
        }
        .sheet(isPresented: $showingAddPet) {
            ProfilePetEditorSheet(title: "Add Pet", pet: nil, isSaving: isSavingPet, errorMessage: petsService.errorMessage) { name, species, breed, sex, age, weight, homeCity, bio in
                guard !isSavingPet else { return false }
                isSavingPet = true
                defer { isSavingPet = false }

                let savedPet = await petsService.addPet(for: user.id, name: name, species: species, breed: breed, sex: sex, age: age, weight: weight, homeCity: homeCity, bio: bio)
                guard savedPet != nil else { return false }

                if let selected = petsService.pets.first(where: { $0.id.uuidString == activePetID }) {
                    activePetID = selected.id.uuidString
                } else if let firstPet = petsService.pets.first {
                    activePetID = firstPet.id.uuidString
                }

                statusMessage = "Pet added"
                return true
            }
        }
        .sheet(item: $editingPet) { pet in
            ProfilePetEditorSheet(title: "Edit Pet", pet: pet, isSaving: isSavingPet, errorMessage: petsService.errorMessage) { name, species, breed, sex, age, weight, homeCity, bio in
                guard !isSavingPet else { return false }
                isSavingPet = true
                defer { isSavingPet = false }

                var updatedPet = pet
                updatedPet.name = name
                updatedPet.species = species
                updatedPet.breed = breed
                updatedPet.sex = sex
                updatedPet.age = age
                updatedPet.weight = weight
                updatedPet.home_city = homeCity
                updatedPet.bio = bio
                await petsService.updatePet(updatedPet, for: user.id)
                if petsService.errorMessage == nil {
                    statusMessage = "Pet updated"
                    return true
                }
                return false
            }
        }
        .sheet(isPresented: $showingEditAccount) {
            ProfileAccountEditorSheet(
                profile: editableProfile,
                fallbackDisplayName: fallbackName,
                isSaving: isSavingProfile,
                errorMessage: profileErrorMessage,
                onSave: { username, displayName, bio in
                    await saveProfile(username: username, displayName: displayName, bio: bio)
                }
            )
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
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 88, height: 88)
                    .overlay {
                        Image(systemName: petIconName)
                            .font(.system(size: 30))
                            .foregroundStyle(.gray)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text(activePet?.name ?? "No Active Pet")
                        .font(.system(size: 26, weight: .semibold))
                    Text(activePetSummary)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    if let ownerLine {
                        Text(ownerLine)
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }

            if let activePet, let bio = trimmed(activePet.bio) {
                Text(bio)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if petsService.isLoading && petsService.pets.isEmpty {
                feedbackCard(icon: nil, text: "Loading pets", tint: .secondary, showsProgress: true)
            }

            HStack(spacing: 12) {
                if let activePet {
                    Button {
                        editingPet = activePet
                    } label: {
                        actionPill(title: "Edit Pet", systemImage: "square.and.pencil")
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
                        actionPill(title: activePet == nil ? "Choose Pet" : "Switch Pet", systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.plain)
                }
            }

            if let statusMessage {
                feedbackCard(icon: "checkmark.circle", text: statusMessage, tint: .green)
            } else if let errorMessage = petsService.errorMessage {
                feedbackCard(icon: "exclamationmark.circle", text: errorMessage, tint: .red)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var petsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                Button("Add") {
                    showingAddPet = true
                }
                .font(.system(size: 15, weight: .medium))
            }

            VStack(alignment: .leading, spacing: 0) {
                if petsService.pets.isEmpty, petsService.isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading pets")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                } else if petsService.pets.isEmpty {
                    HStack {
                        Text("No pets yet")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
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
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var petDetailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let activePet {
                VStack(spacing: 0) {
                    ForEach(Array(petDetailRows(for: activePet).enumerated()), id: \.offset) { index, row in
                        detailRow(title: row.title, value: row.value)

                        if index < petDetailRows(for: activePet).count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Choose or add a pet to see profile details.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private func petRow(_ pet: RemotePet) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
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
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 64, height: 64)
                        .overlay {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.gray)
                        }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(accountDisplayName)
                            .font(.system(size: 22, weight: .semibold))
                        Text(profileHandle)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        showingEditAccount = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 38, height: 38)
                            .background(Color(.secondarySystemBackground).opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if isLoadingProfile {
                    feedbackCard(icon: nil, text: "Loading account", tint: .secondary, showsProgress: true)
                } else if let profileErrorMessage {
                    feedbackCard(icon: "exclamationmark.circle", text: profileErrorMessage, tint: .red)
                }

                VStack(spacing: 0) {
                    detailRow(title: "Display Name", value: accountDisplayName)
                    Divider().padding(.leading, 16)
                    detailRow(title: "Username", value: profile?.username ?? "Not set")
                    Divider().padding(.leading, 16)
                    detailRow(title: "Bio", value: profile?.bio ?? "Not set")
                    Divider().padding(.leading, 16)
                    detailRow(title: "Email", value: user.email ?? "")
                }
                .background(Color(.secondarySystemBackground).opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(18)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var signOutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var accountDisplayName: String {
        let displayName = profile?.display_name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        return user.displayName ?? fallbackName
    }

    private var profileHandle: String {
        if let username = trimmed(profile?.username) {
            return "@\(username)"
        }
        return user.email ?? ""
    }

    private var ownerLine: String? {
        let source = trimmed(profile?.username) ?? trimmed(accountDisplayName)
        guard let source else { return nil }
        return "by \(source)"
    }

    private var editableProfile: RemoteProfile {
        profile ?? RemoteProfile(id: user.id, username: nil, display_name: user.displayName, bio: nil, avatar_url: nil)
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

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func actionPill(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
            Text(title)
                .font(.system(size: 15, weight: .medium))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func feedbackCard(icon: String?, text: String, tint: Color, showsProgress: Bool = false) -> some View {
        HStack(spacing: 10) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else if let icon {
                Image(systemName: icon)
                    .foregroundStyle(tint)
            }

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func loadProfile() async {
        isLoadingProfile = true
        profileErrorMessage = nil
        defer { isLoadingProfile = false }

        do {
            profile = try await profileService.loadProfile(for: user.id)
        } catch {
            profileErrorMessage = error.localizedDescription
        }
    }

    private func saveProfile(username: String, displayName: String, bio: String) async -> Bool {
        guard !isSavingProfile else { return false }
        isSavingProfile = true
        profileErrorMessage = nil
        defer { isSavingProfile = false }

        do {
            profile = try await profileService.saveProfile(for: user.id, username: username, displayName: displayName, bio: bio)
            statusMessage = "Account updated"
            return true
        } catch {
            profileErrorMessage = error.localizedDescription
            return false
        }
    }

    private var activePetSummary: String {
        guard let activePet else { return "Choose or create a pet" }
        let details = [activePet.species, activePet.breed]
            .compactMap { trimmed($0) }
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
        [pet.species, pet.breed]
            .compactMap { trimmed($0) }
            .joined(separator: " · ")
    }

    private func petDetailRows(for pet: RemotePet) -> [(title: String, value: String)] {
        [
            ("Breed", trimmed(pet.breed) ?? "Not set"),
            ("Age", trimmed(pet.age) ?? "Not set"),
            ("Weight", trimmed(pet.weight) ?? "Not set"),
            ("Hometown", trimmed(pet.home_city) ?? "Not set")
        ]
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
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
    @State private var sex: String
    @State private var ageValue: String
    @State private var ageUnit: String
    @State private var weightValue: String
    @State private var weightUnit: String
    @State private var selectedCountry: String
    @State private var selectedRegion: String
    @State private var selectedCity: String
    @State private var showingLocationPicker = false
    @State private var bio: String

    private let ageUnits = ["years", "months"]
    private let weightUnits = ["lb", "kg"]
    private let hometownTree: [String: [String: [String]]] = [
        "United States": [
            "Washington": ["Seattle", "Bellevue", "Lynnwood", "Redmond", "Kirkland", "Everett"],
            "California": ["San Francisco", "San Jose", "Los Angeles", "San Diego"]
        ],
        "Canada": [
            "British Columbia": ["Vancouver", "Burnaby", "Richmond"],
            "Ontario": ["Toronto", "Ottawa", "Waterloo"]
        ]
    ]

    let title: String
    let isSaving: Bool
    let errorMessage: String?
    let onSave: (String, String, String, String, String, String, String, String) async -> Bool

    init(title: String, pet: RemotePet?, isSaving: Bool, errorMessage: String?, onSave: @escaping (String, String, String, String, String, String, String, String) async -> Bool) {
        self.title = title
        self.isSaving = isSaving
        self.errorMessage = errorMessage
        self.onSave = onSave
        _name = State(initialValue: pet?.name ?? "")
        _species = State(initialValue: pet?.species?.isEmpty == false ? pet?.species ?? "Dog" : "Dog")
        _breed = State(initialValue: pet?.breed ?? "")
        _sex = State(initialValue: pet?.sex ?? "")
        let parsedAge = Self.splitMeasurement(pet?.age, fallbackUnit: "years")
        _ageValue = State(initialValue: parsedAge.value)
        _ageUnit = State(initialValue: parsedAge.unit)
        let parsedWeight = Self.splitMeasurement(pet?.weight, fallbackUnit: "lb")
        _weightValue = State(initialValue: parsedWeight.value)
        _weightUnit = State(initialValue: parsedWeight.unit)
        let parsedLocation = Self.splitLocation(pet?.home_city)
        _selectedCountry = State(initialValue: parsedLocation.country)
        _selectedRegion = State(initialValue: parsedLocation.region)
        _selectedCity = State(initialValue: parsedLocation.city)
        _bio = State(initialValue: pet?.bio ?? "")
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
                                .onChange(of: species) { _, newValue in
                                    breed = breedOptions(for: newValue).first ?? "Mixed"
                                }
                            }
                            Divider().padding(.leading, 16)
                            inputRow(title: "Breed") {
                                Picker("Breed", selection: $breed) {
                                    ForEach(breedOptions(for: species), id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                            Divider().padding(.leading, 16)
                            inputRow(title: "Sex") {
                                Picker("Sex", selection: $sex) {
                                    Text("Not set").tag("")
                                    Text("Male").tag("Male")
                                    Text("Female").tag("Female")
                                }
                                .pickerStyle(.menu)
                            }
                            Divider().padding(.leading, 16)
                            inputRow(title: "Age") {
                                HStack(spacing: 10) {
                                    TextField("Optional", text: $ageValue)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                    Picker("Age Unit", selection: $ageUnit) {
                                        ForEach(ageUnits, id: \.self) { unit in
                                            Text(unit).tag(unit)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }
                            }
                            Divider().padding(.leading, 16)
                            inputRow(title: "Weight") {
                                HStack(spacing: 10) {
                                    TextField("Optional", text: $weightValue)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                    Picker("Weight Unit", selection: $weightUnit) {
                                        ForEach(weightUnits, id: \.self) { unit in
                                            Text(unit).tag(unit)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }
                            }
                            Divider().padding(.leading, 16)
                            Button {
                                showingLocationPicker = true
                            } label: {
                                inputRow(title: "Hometown") {
                                    HStack(spacing: 8) {
                                        Text(locationSummary)
                                            .foregroundStyle(.secondary)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Bio")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)

                            TextField("Optional", text: $bio, axis: .vertical)
                                .lineLimit(3...6)
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
                                let didSave = await onSave(name, species, breed, sex, composedAge, composedWeight, composedLocation, bio)
                                if didSave {
                                    dismiss()
                                }
                            }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(canSave ? Color.black : Color(.tertiarySystemFill))
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
            .sheet(isPresented: $showingLocationPicker) {
                NavigationStack {
                    Form {
                        Picker("Country", selection: $selectedCountry) {
                            ForEach(countries, id: \.self) { country in
                                Text(country).tag(country)
                            }
                        }
                        .onChange(of: selectedCountry) { _, newValue in
                            selectedRegion = regions(for: newValue).first ?? ""
                            selectedCity = cities(for: newValue, region: selectedRegion).first ?? ""
                        }

                        Picker("State", selection: $selectedRegion) {
                            ForEach(regions(for: selectedCountry), id: \.self) { region in
                                Text(region).tag(region)
                            }
                        }
                        .onChange(of: selectedRegion) { _, newValue in
                            selectedCity = cities(for: selectedCountry, region: newValue).first ?? ""
                        }

                        Picker("City", selection: $selectedCity) {
                            ForEach(cities(for: selectedCountry, region: selectedRegion), id: \.self) { city in
                                Text(city).tag(city)
                            }
                        }
                    }
                    .navigationTitle("Choose Hometown")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingLocationPicker = false }
                        }
                    }
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func inputRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)

            content()
                .font(.system(size: 16))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private var composedAge: String {
        Self.composeMeasurement(value: ageValue, unit: ageUnit)
    }

    private var composedWeight: String {
        Self.composeMeasurement(value: weightValue, unit: weightUnit)
    }

    private var countries: [String] {
        hometownTree.keys.sorted()
    }

    private func breedOptions(for species: String) -> [String] {
        switch species {
        case "Dog":
            return ["Mixed", "Golden Retriever", "Labrador", "Poodle", "French Bulldog", "Corgi", "Shiba Inu"]
        case "Cat":
            return ["Mixed", "British Shorthair", "Ragdoll", "Siamese", "Maine Coon", "American Shorthair"]
        default:
            return ["Mixed", "Other"]
        }
    }

    private func regions(for country: String) -> [String] {
        hometownTree[country]?.keys.sorted() ?? []
    }

    private func cities(for country: String, region: String) -> [String] {
        hometownTree[country]?[region] ?? []
    }

    private var composedLocation: String {
        [selectedCountry, selectedRegion, selectedCity]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var locationSummary: String {
        let city = selectedCity.isEmpty ? "City" : selectedCity
        let regionCode = abbreviation(for: selectedRegion)
        let countryCode = abbreviation(for: selectedCountry)
        return [city, regionCode, countryCode]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private static func splitMeasurement(_ raw: String?, fallbackUnit: String) -> (value: String, unit: String) {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return ("", fallbackUnit)
        }

        let parts = raw.split(separator: " ", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return (parts[0], parts[1])
        }
        return (raw, fallbackUnit)
    }

    private static func composeMeasurement(value: String, unit: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return "" }
        return "\(trimmedValue) \(unit)"
    }

    private static func splitLocation(_ raw: String?) -> (country: String, region: String, city: String) {
        let defaults = (country: "United States", region: "Washington", city: "Seattle")
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return defaults
        }

        let parts = raw.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if parts.count == 3 {
            return (parts[0], parts[1], parts[2])
        }
        return defaults
    }

    private func abbreviation(for value: String) -> String {
        switch value {
        case "United States": return "US"
        case "Canada": return "CA"
        case "Washington": return "WA"
        case "California": return "CA"
        case "British Columbia": return "BC"
        case "Ontario": return "ON"
        default: return value
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

private struct ProfileAccountEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var username: String
    @State private var displayName: String
    @State private var bio: String

    let isSaving: Bool
    let errorMessage: String?
    let onSave: (String, String, String) async -> Bool

    init(profile: RemoteProfile, fallbackDisplayName: String, isSaving: Bool, errorMessage: String?, onSave: @escaping (String, String, String) async -> Bool) {
        self.isSaving = isSaving
        self.errorMessage = errorMessage
        self.onSave = onSave
        _username = State(initialValue: profile.username ?? "")
        _displayName = State(initialValue: profile.display_name ?? fallbackDisplayName)
        _bio = State(initialValue: profile.bio ?? "")
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
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(.gray)
                                }

                            Text("Edit Account")
                                .font(.system(size: 24, weight: .semibold))
                        }
                        .padding(.top, 20)

                        VStack(spacing: 0) {
                            inputRow(title: "Username") {
                                TextField("Required", text: $username)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            Divider().padding(.leading, 16)
                            inputRow(title: "Display") {
                                TextField("Optional", text: $displayName)
                            }
                        }
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Bio")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)

                            TextField("Optional", text: $bio, axis: .vertical)
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
                                let didSave = await onSave(username, displayName, bio)
                                if didSave {
                                    dismiss()
                                }
                            }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(canSave ? Color.black : Color(.tertiarySystemFill))
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
            .navigationTitle("Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var canSave: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
}
