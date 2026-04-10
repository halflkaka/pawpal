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
            VStack(alignment: .leading, spacing: 24) {
                profileTitleBar
                activePetSection
                petsSection
                accountSection
                signOutSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(profileBackground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
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

    private var profileTitleBar: some View {
        HStack(alignment: .center) {
            HStack(spacing: 10) {
                Text("🐶")
                    .font(.system(size: 28))
                Text("My Pets")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(titleColor)
            }

            Spacer()

            Button {
                showingAddPet = true
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accentGreen)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private var activePetSection: some View {
        if let activePet {
            VStack(alignment: .leading, spacing: 18) {
                petSummaryHeader(activePet)
                petOverview(activePet)

                if let bio = trimmed(activePet.bio) {
                    simpleMultilineRow(title: "About", value: bio)
                }

                petActionBar(activePet)

                if let statusMessage {
                    statusBanner(text: statusMessage, tint: .green, icon: "checkmark.circle")
                } else if let errorMessage = petsService.errorMessage {
                    statusBanner(text: errorMessage, tint: .red, icon: "exclamationmark.circle")
                } else if petsService.isLoading && petsService.pets.isEmpty {
                    loadingBanner("Loading pets")
                }
            }
            .profileCardStyle()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("No Active Pet")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(titleColor)
                Text("Choose or add a pet to see profile details.")
                    .foregroundStyle(.secondary)
                Button("Add Pet") {
                    showingAddPet = true
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accentGreen)
            }
            .profileCardStyle()
        }
    }

    private var petsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading("All Pets")

            if petsService.pets.isEmpty, petsService.isLoading {
                loadingRow("Loading pets")
                    .profileCardStyle()
            } else if petsService.pets.isEmpty {
                emptyRow("No pets yet")
                    .profileCardStyle()
            } else {
                ForEach(petsService.pets) { pet in
                    petListRow(pet)
                }
            }
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading("Account")

            VStack(spacing: 0) {
                accountHeader
                Divider().padding(.horizontal, 18)
                detailLine(title: "Display Name", value: accountDisplayName)
                Divider().padding(.horizontal, 18)
                detailLine(title: "Username", value: profile?.username ?? "Not set")
                Divider().padding(.horizontal, 18)
                detailLine(title: "Bio", value: profile?.bio ?? "Not set", multiline: true)
                Divider().padding(.horizontal, 18)
                detailLine(title: "Email", value: user.email ?? "", multiline: true)
            }
            .profileCardStyle(padding: 0)

            if isLoadingProfile {
                loadingBanner("Loading account")
                    .profileCardStyle()
            } else if let profileErrorMessage {
                statusBanner(text: profileErrorMessage, tint: .red, icon: "exclamationmark.circle")
                    .profileCardStyle()
            }
        }
    }

    private var signOutSection: some View {
        HStack(spacing: 14) {
            Button(role: .destructive) {
                authManager.signOut()
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(Color(red: 0.83, green: 0.43, blue: 0.43))
            .padding(.vertical, 18)
            .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func petSummaryHeader(_ pet: RemotePet) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Circle()
                .fill(Color.white)
                .frame(width: 78, height: 78)
                .overlay(
                    Image(systemName: iconName(for: pet.species ?? ""))
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(accentOrange)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(pet.name)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Circle()
                        .fill(statusColor(for: pet))
                        .frame(width: 10, height: 10)
                }

                statsPillRow(for: pet)
            }

            Spacer()
        }
    }

    private func petOverview(_ pet: RemotePet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            detailFeatureRow(
                title: "Hometown",
                value: trimmed(pet.home_city) ?? "Not set"
            )

            if let breed = trimmed(pet.breed), !breed.isEmpty {
                detailFeatureRow(title: "Breed", value: breed)
            }
        }
    }

    private func petActionBar(_ pet: RemotePet) -> some View {
        HStack(spacing: 12) {
            Button {
                editingPet = pet
            } label: {
                Text("Edit")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 0.95, green: 0.94, blue: 0.86), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(accentGreen)

            Menu {
                ForEach(petsService.pets) { pet in
                    Button(pet.name) {
                        activePetID = pet.id.uuidString
                        statusMessage = "Active pet updated"
                    }
                }
            } label: {
                Text("Switch")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.75), in: Capsule())
            }
            .foregroundStyle(titleColor)
        }
    }

    private var accountHeader: some View {
        Button {
            showingEditAccount = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(accountDisplayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(profileHandle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func petListRow(_ pet: RemotePet) -> some View {
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
            HStack(spacing: 14) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: iconName(for: pet.species ?? ""))
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(accentOrange)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(pet.name)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(titleColor)
                            .lineLimit(1)
                        Circle()
                            .fill(statusColor(for: pet))
                            .frame(width: 10, height: 10)
                    }

                    HStack(spacing: 8) {
                        petInfoPill(systemImage: "birthday.cake", text: trimmed(pet.age) ?? "Not set", tint: accentOrange)
                        petInfoPill(systemImage: "scalemass", text: trimmed(pet.weight) ?? "Not set", tint: accentGreen)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 10) {
                    Text("Edit")
                        .font(.system(size: 15, weight: .medium))
                    Text("Delete")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
            .padding(18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .profileCardStyle(padding: 0)
    }

    private var profileBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.95, blue: 0.90),
                Color(red: 0.99, green: 0.97, blue: 0.94)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var titleColor: Color {
        Color(red: 0.33, green: 0.27, blue: 0.22)
    }

    private var accentOrange: Color {
        Color(red: 0.90, green: 0.55, blue: 0.29)
    }

    private var accentGreen: Color {
        Color(red: 0.52, green: 0.66, blue: 0.48)
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(titleColor)
            .padding(.horizontal, 4)
    }

    private func statsPillRow(for pet: RemotePet) -> some View {
        HStack(spacing: 8) {
            petInfoPill(systemImage: "birthday.cake", text: trimmed(pet.age) ?? "Not set", tint: accentOrange)
            petInfoPill(systemImage: "scalemass", text: trimmed(pet.weight) ?? "Not set", tint: accentGreen)
        }
    }

    private func petInfoPill(systemImage: String, text: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.10), in: Capsule())
    }

    private func statusColor(for pet: RemotePet) -> Color {
        pet.id.uuidString == activePetID ? accentOrange : accentGreen.opacity(0.75)
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

    private func healthFactGrid(for pet: RemotePet) -> some View {
        HStack(spacing: 12) {
            factTile(title: "Breed", value: trimmed(pet.breed) ?? "Not set")
            factTile(title: "Age", value: trimmed(pet.age) ?? "Not set")
            factTile(title: "Weight", value: trimmed(pet.weight) ?? "Not set")
        }
    }

    private func factTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func detailFeatureRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(titleColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(Color(red: 0.98, green: 0.97, blue: 0.94), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func detailLine(title: String, value: String, multiline: Bool = false) -> some View {
        HStack(alignment: multiline ? .top : .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: multiline)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func simpleMultilineRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16))
                .foregroundStyle(titleColor)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
        .padding(16)
        .background(Color(red: 0.98, green: 0.97, blue: 0.94), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func loadingRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private func emptyRow(_ text: String) -> some View {
        HStack {
            Text(text)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private func loadingBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
    }

    private func statusBanner(text: String, tint: Color, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
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

private extension View {
    func profileCardStyle(padding: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 18, y: 8)
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
