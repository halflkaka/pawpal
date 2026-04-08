import SwiftUI

struct RemotePetsView: View {
    let user: AppUser
    @StateObject private var petsService = PetsService()
    @State private var showingAddPet = false

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Your Pets")
                        .font(.headline)
                    Spacer()
                    Button("Add Pet") {
                        showingAddPet = true
                    }
                }
            }

            if petsService.isLoading {
                Section {
                    ProgressView()
                }
            } else if let errorMessage = petsService.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            } else if petsService.pets.isEmpty {
                Section {
                    Text("No pets yet")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(petsService.pets) { pet in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pet.name)
                            .font(.headline)
                        Text([pet.species, pet.breed].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " • "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Pets")
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
