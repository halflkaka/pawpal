import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredPetProfile.name) private var storedPets: [StoredPetProfile]
    @Query(sort: \StoredSymptomCheck.date, order: .reverse) private var storedChecks: [StoredSymptomCheck]

    private var pet: StoredPetProfile? {
        storedPets.first
    }

    var body: some View {
        List {
            Section("Pet") {
                if let pet {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pet.name.isEmpty ? "Your Pet" : pet.name)
                            .font(.headline)
                        Text(displayLine(for: pet))
                            .foregroundStyle(.secondary)
                        Text(detailLine(for: pet))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No pet profile yet")
                        .foregroundStyle(.secondary)
                }

                NavigationLink("Edit Pet Profile") {
                    PetProfileView()
                }
            }

            Section("Actions") {
                NavigationLink("Check Symptoms") {
                    SymptomCheckView(pet: pet)
                }

                NavigationLink("Find Nearby Vet") {
                    VetFinderView()
                }

                NavigationLink("History") {
                    HistoryView()
                }
            }

            Section("Recent Checks") {
                if storedChecks.isEmpty {
                    Text("No saved checks yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(storedChecks.prefix(3)) { check in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(check.symptomText)
                                .font(.headline)
                            Text(check.urgency.capitalized)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Pet Health")
        .task {
            if storedPets.isEmpty {
                modelContext.insert(StoredPetProfile(name: "", species: "Dog", breed: "", age: "", weight: "", notes: ""))
            }
        }
    }

    private func displayLine(for pet: StoredPetProfile) -> String {
        let parts = [pet.species, pet.breed].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return parts.isEmpty ? "Add species and breed" : parts.joined(separator: " • ")
    }

    private func detailLine(for pet: StoredPetProfile) -> String {
        let age = pet.age.trimmingCharacters(in: .whitespacesAndNewlines)
        let weight = pet.weight.trimmingCharacters(in: .whitespacesAndNewlines)

        if age.isEmpty && weight.isEmpty { return "Add age and weight" }
        if age.isEmpty { return "Weight: \(weight)" }
        if weight.isEmpty { return "Age: \(age)" }
        return "Age: \(age) • Weight: \(weight)"
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .modelContainer(for: [StoredPetProfile.self, StoredSymptomCheck.self], inMemory: true)
}
