import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredPetProfile.name) private var storedPets: [StoredPetProfile]
    @Query(sort: \StoredSymptomCheck.date, order: .reverse) private var storedChecks: [StoredSymptomCheck]
    @AppStorage("selectedPetID") private var selectedPetID = ""

    private var selectedPet: StoredPetProfile? {
        if let match = storedPets.first(where: { $0.id.uuidString == selectedPetID }) {
            return match
        }
        return storedPets.first
    }

    private var filteredChecks: [StoredSymptomCheck] {
        guard let selectedPet else { return storedChecks }
        return storedChecks.filter { check in
            if let petID = check.petID {
                return petID == selectedPet.id
            }
            return true
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                petCard
                quickActions
                recentChecksSection
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Pet Health")
        .task {
            if storedPets.isEmpty {
                let pet = StoredPetProfile(name: "", species: "Dog", breed: "", age: "", weight: "", notes: "")
                modelContext.insert(pet)
                selectedPetID = pet.id.uuidString
            } else if selectedPet == nil, let firstPet = storedPets.first {
                selectedPetID = firstPet.id.uuidString
            }
        }
    }

    private var petCard: some View {
        NavigationLink {
            PetProfileView()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(storedPets.count > 1 ? "Current Pet" : "Pet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Label("Manage", systemImage: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                }

                if let pet = selectedPet {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(pet.name.isEmpty ? "Your Pet" : pet.name)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.primary)
                        Text(displayLine(for: pet))
                            .foregroundStyle(.secondary)
                        Text(detailLine(for: pet))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if storedPets.count > 1 {
                            Picker("Selected Pet", selection: $selectedPetID) {
                                ForEach(storedPets) { pet in
                                    Text(pet.name.isEmpty ? "Unnamed Pet" : pet.name)
                                        .tag(pet.id.uuidString)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                } else {
                    Text("No pet profile yet")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.blue.opacity(0.16), Color.teal.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            NavigationLink {
                SymptomCheckView(pet: selectedPet)
            } label: {
                actionCard(
                    title: "Check Symptoms",
                    subtitle: selectedPet == nil ? "Describe what’s going on and get guidance" : "Analyze symptoms for \(selectedPetName(fallback: "your pet"))",
                    systemImage: "stethoscope",
                    tint: .blue
                )
            }

            NavigationLink {
                VetFinderView()
            } label: {
                actionCard(
                    title: "Find Nearby Vet",
                    subtitle: "See local clinics and emergency care",
                    systemImage: "cross.case.fill",
                    tint: .red
                )
            }

            NavigationLink {
                HistoryView(selectedPetID: selectedPet?.id)
            } label: {
                actionCard(
                    title: "View History",
                    subtitle: "Open saved symptom checks",
                    systemImage: "clock.arrow.circlepath",
                    tint: .orange
                )
            }

            NavigationLink {
                PetProfileView()
            } label: {
                actionCard(
                    title: "Add or Manage Pets",
                    subtitle: "Create another pet profile or switch the active pet",
                    systemImage: "pawprint.circle.fill",
                    tint: .teal
                )
            }
        }
    }

    private var recentChecksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Checks")
                .font(.headline)

            if filteredChecks.isEmpty {
                cardContainer {
                    Text(selectedPet == nil ? "No saved checks yet" : "No saved checks yet for \(selectedPetName(fallback: "this pet"))")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(filteredChecks.prefix(3)) { check in
                    NavigationLink {
                        ResultView(
                            petName: displayPetName(for: check),
                            symptomText: check.symptomText,
                            durationText: check.durationText,
                            extraNotes: check.extraNotes,
                            result: check.toAnalysisResult()
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(check.urgency.capitalized)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(urgencyColor(for: check.urgency).opacity(0.14))
                                    .foregroundStyle(urgencyColor(for: check.urgency))
                                    .clipShape(Capsule())
                                Spacer()
                                Text(check.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if !displayPetName(for: check).isEmpty {
                                Label(displayPetName(for: check), systemImage: "pawprint.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            Text(check.symptomText)
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func actionCard(title: String, subtitle: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.14))
                .foregroundStyle(tint)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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

    private func displayPetName(for check: StoredSymptomCheck) -> String {
        let trimmed = check.petName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
    }

    private func selectedPetName(fallback: String) -> String {
        guard let selectedPet else { return fallback }
        let trimmed = selectedPet.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func urgencyColor(for urgency: String) -> Color {
        switch urgency {
        case "emergency": return .red
        case "soon": return .orange
        default: return .blue
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .modelContainer(for: [StoredPetProfile.self, StoredSymptomCheck.self], inMemory: true)
}
