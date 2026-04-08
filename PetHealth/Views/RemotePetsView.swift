import SwiftUI

struct RemotePetsView: View {
    let user: AppUser
    @StateObject private var petsService = PetsService()
    @State private var showingAddPet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard

                if petsService.isLoading {
                    loadingCard
                } else if let errorMessage = petsService.errorMessage {
                    errorCard(errorMessage)
                } else if petsService.pets.isEmpty {
                    emptyCard
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(petsService.pets) { pet in
                            petCard(pet)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Pets")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await petsService.loadPets(for: user.id)
        }
        .sheet(isPresented: $showingAddPet) {
            RemoteAddPetSheet { name, species, breed, age, weight, notes in
                Task {
                    await petsService.addPet(for: user.id, name: name, species: species, breed: breed, age: age, weight: weight, notes: notes)
                }
            }
        }
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color.orange.opacity(0.14))
                .frame(width: 54, height: 54)
                .overlay {
                    Image(systemName: "pawprint.fill")
                        .foregroundStyle(.orange)
                }

            Text("Pets")
                .font(.system(size: 30, weight: .bold))

            Spacer()

            Button {
                showingAddPet = true
            } label: {
                Image(systemName: "plus")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.16), Color.yellow.opacity(0.08), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var loadingCard: some View {
        VStack {
            ProgressView()
                .padding(.vertical, 28)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func errorCard(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.red)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "pawprint.circle")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("No pets yet")
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func petCard(_ pet: RemotePet) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.orange.opacity(0.12))
                .frame(width: 58, height: 58)
                .overlay {
                    Image(systemName: iconName(for: pet.species ?? ""))
                        .font(.title3)
                        .foregroundStyle(.orange)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(pet.name)
                    .font(.headline)

                let detail = [pet.species, pet.breed, pet.age]
                    .compactMap { $0 }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " • ")

                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
    @State private var age = ""
    @State private var weight = ""
    @State private var notes = ""

    let onSave: (String, String, String, String, String, String) -> Void

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
                TextField("Age", text: $age)
                TextField("Weight", text: $weight)
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
                        onSave(name, species, breed, age, weight, notes)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
