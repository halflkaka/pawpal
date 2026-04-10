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
            VStack(alignment: .leading, spacing: 22) {
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
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("Active Pet")

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
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel("My Pets")
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
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Pet Details")

            VStack(spacing: 0) {
                detailRow(title: "Species", value: activePet?.species ?? "Not set")
                Divider().padding(.leading, 16)
                detailRow(title: "Breed", value: activePet?.breed ?? "Not set")
                Divider().padding(.leading, 16)
                detailRow(title: "Sex", value: activePet?.sex ?? "Not set")
                Divider().padding(.leading, 16)
                detailRow(title: "Age", value: activePet?.age ?? "Not set")
                Divider().padding(.leading, 16)
                detailRow(title: "Weight", value: activePet?.weight ?? "Not set")
                Divider().padding(.leading, 16)
                detailRow(title: "Home City", value: activePet?.home_city ?? "Not set")
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Account")

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
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Session")

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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 16))
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
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
        let details = [activePet.species, activePet.breed, activePet.sex, activePet.age, activePet.home_city]
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
        [pet.species, pet.breed, pet.sex, pet.age, pet.home_city]
            .compactMap { trimmed($0) }
            .joined(separator: " · ")
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
    @State private var age: String
    @State private var weight: String
    @State private var homeCity: String
    @State private var bio: String

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
        _age = State(initialValue: pet?.age ?? "")
        _weight = State(initialValue: pet?.weight ?? "")
        _homeCity = State(initialValue: pet?.home_city ?? "")
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
                            }
                            Divider().padding(.leading, 16)
                            inputRow(title: "Breed") {
                                TextField("Optional", text: $breed)
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
                                TextField("Optional", text: $age)
                            }
                            Divider().padding(.leading, 16)
                            inputRow(title: "Weight") {
                                TextField("Optional", text: $weight)
                            }
                            Divider().padding(.leading, 16)
                            inputRow(title: "Home City") {
                                TextField("Optional", text: $homeCity)
                                    .textInputAutocapitalization(.words)
                            }
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
                                let didSave = await onSave(name, species, breed, sex, age, weight, homeCity, bio)
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
