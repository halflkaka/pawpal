import SwiftUI
import SwiftData

struct PetProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredPetProfile.name) private var storedPets: [StoredPetProfile]

    private var pet: StoredPetProfile? {
        storedPets.first
    }

    var body: some View {
        Form {
            if let pet {
                TextField("Name", text: binding(for: pet, keyPath: \.name))
                TextField("Species", text: binding(for: pet, keyPath: \.species))
                TextField("Breed", text: binding(for: pet, keyPath: \.breed))
                TextField("Age", text: binding(for: pet, keyPath: \.age))
                TextField("Weight", text: binding(for: pet, keyPath: \.weight))
                TextField("Notes", text: binding(for: pet, keyPath: \.notes), axis: .vertical)
                    .lineLimit(3...6)
            } else {
                Text("Creating pet profile...")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Pet Profile")
        .task {
            if storedPets.isEmpty {
                modelContext.insert(StoredPetProfile(name: "", species: "Dog", breed: "", age: "", weight: "", notes: ""))
            }
        }
    }

    private func binding(for pet: StoredPetProfile, keyPath: ReferenceWritableKeyPath<StoredPetProfile, String>) -> Binding<String> {
        Binding(
            get: { pet[keyPath: keyPath] },
            set: { pet[keyPath: keyPath] = $0 }
        )
    }
}
