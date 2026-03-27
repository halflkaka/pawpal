import SwiftUI

struct HomeView: View {
    @StateObject private var petVM = PetProfileViewModel()
    @StateObject private var historyVM = HistoryViewModel()

    var body: some View {
        List {
            Section("Pet") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(petVM.pet.name.isEmpty ? "Your Pet" : petVM.pet.name)
                        .font(.headline)
                    Text("\(petVM.pet.species) • \(petVM.pet.breed)")
                        .foregroundStyle(.secondary)
                    Text("Age: \(petVM.pet.age) • Weight: \(petVM.pet.weight)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                NavigationLink("Edit Pet Profile") {
                    PetProfileView(viewModel: petVM)
                }
            }

            Section("Actions") {
                NavigationLink("Check Symptoms") {
                    SymptomCheckView(pet: petVM.pet, historyViewModel: historyVM)
                }

                NavigationLink("Find Nearby Vet") {
                    VetFinderView()
                }

                NavigationLink("History") {
                    HistoryView(viewModel: historyVM)
                }
            }

            Section("Recent Checks") {
                ForEach(historyVM.checks.prefix(3)) { check in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(check.symptomText)
                            .font(.headline)
                        Text(check.result.urgency.capitalized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Pet Health")
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
}
