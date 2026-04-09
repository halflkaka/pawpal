import SwiftUI

struct FirstPetSetupView: View {
    let user: AppUser
    let onComplete: (RemotePet) -> Void

    @StateObject private var petsService = PetsService()
    @State private var name = ""
    @State private var species = "Dog"
    @State private var breed = ""
    @State private var age = ""
    @State private var weight = ""
    @State private var notes = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: 72, height: 72)
                            .overlay {
                                Image(systemName: "pawprint.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.gray)
                            }

                        Text("Create your first pet")
                            .font(.system(size: 24, weight: .semibold))

                        Text("This will be your active pet")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 28)

                    VStack(spacing: 0) {
                        row(title: "Name") {
                            TextField("Pet name", text: $name)
                        }
                        Divider().padding(.leading, 16)
                        row(title: "Species") {
                            Picker("Species", selection: $species) {
                                Text("Dog").tag("Dog")
                                Text("Cat").tag("Cat")
                                Text("Other").tag("Other")
                            }
                            .pickerStyle(.menu)
                        }
                        Divider().padding(.leading, 16)
                        row(title: "Breed") {
                            TextField("Optional", text: $breed)
                        }
                        Divider().padding(.leading, 16)
                        row(title: "Age") {
                            TextField("Optional", text: $age)
                        }
                    }
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Optional")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text("You can add more details later in Profile.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    if let errorMessage = petsService.errorMessage {
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
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    }

                    if isSaving && petsService.errorMessage == nil {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Finishing setup")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    }

                    Button {
                        Task {
                            await save()
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
                                Text("Continue")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(canSave ? .white : .secondary)
                            }
                        }
                    }
                    .disabled(!canSave || isSaving)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarBackButtonHidden(true)
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        petsService.errorMessage = nil
        defer { isSaving = false }

        await petsService.addPet(
            for: user.id,
            name: name,
            species: species,
            breed: breed,
            age: age,
            weight: weight,
            notes: notes
        )

        await petsService.loadPets(for: user.id)

        guard let pet = petsService.pets.first else {
            if petsService.errorMessage == nil {
                petsService.errorMessage = "Could not load the pet after saving. Please try again."
            }
            return
        }

        onComplete(pet)
    }

    private func row<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
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
