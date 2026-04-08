import SwiftUI

struct ProfileView: View {
    let user: AppUser
    @Bindable var authManager: AuthManager
    @AppStorage("activePetID") private var activePetID = ""
    @StateObject private var petsService = PetsService()
    @State private var showingAddPet = false

    private var activePet: RemotePet? {
        if let match = petsService.pets.first(where: { $0.id.uuidString == activePetID }) {
            return match
        }
        return petsService.pets.first
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                petHero
                petsSection
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
        .sheet(isPresented: $showingAddPet) {
            RemoteAddPetSheet { name, species, breed, age, weight, notes in
                Task {
                    await petsService.addPet(for: user.id, name: name, species: species, breed: breed, age: age, weight: weight, notes: notes)
                    if let firstPet = petsService.pets.first(where: { $0.id.uuidString == activePetID }) {
                        activePetID = firstPet.id.uuidString
                    } else if let firstPet = petsService.pets.first {
                        activePetID = firstPet.id.uuidString
                    }
                }
            }
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

            if !petsService.pets.isEmpty {
                Menu {
                    ForEach(petsService.pets) { pet in
                        Button(pet.name) {
                            activePetID = pet.id.uuidString
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

            if petsService.pets.isEmpty {
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
                }

                Button("Delete", role: .destructive) {
                    Task {
                        let deletingActive = pet.id.uuidString == activePetID
                        await petsService.deletePet(pet.id, for: user.id)
                        if deletingActive {
                            activePetID = petsService.pets.first?.id.uuidString ?? ""
                        }
                    }
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
