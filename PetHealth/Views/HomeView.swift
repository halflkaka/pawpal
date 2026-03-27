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
                modelContext.insert(StoredPetProfile(name: "", species: "Dog", breed: "", age: "", weight: "", notes: ""))
            }
        }
    }

    private var petCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Pet")
                .font(.headline)
                .foregroundStyle(.secondary)

            if let pet {
                VStack(alignment: .leading, spacing: 8) {
                    Text(pet.name.isEmpty ? "Your Pet" : pet.name)
                        .font(.system(size: 28, weight: .bold))
                    Text(displayLine(for: pet))
                        .foregroundStyle(.secondary)
                    Text(detailLine(for: pet))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        PetProfileView()
                    } label: {
                        Label("Edit Pet Profile", systemImage: "square.and.pencil")
                            .font(.subheadline.weight(.semibold))
                            .padding(.top, 6)
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

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            NavigationLink {
                SymptomCheckView(pet: pet)
            } label: {
                actionCard(
                    title: "Check Symptoms",
                    subtitle: "Describe what’s going on and get guidance",
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
                HistoryView()
            } label: {
                actionCard(
                    title: "View History",
                    subtitle: "Open saved symptom checks",
                    systemImage: "clock.arrow.circlepath",
                    tint: .orange
                )
            }
        }
    }

    private var recentChecksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Checks")
                .font(.headline)

            if storedChecks.isEmpty {
                cardContainer {
                    Text("No saved checks yet")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(storedChecks.prefix(3)) { check in
                    NavigationLink {
                        ResultView(
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
