import SwiftUI

struct PetProfileView: View {
    @ObservedObject var viewModel: PetProfileViewModel

    var body: some View {
        Form {
            TextField("Name", text: $viewModel.pet.name)
            TextField("Species", text: $viewModel.pet.species)
            TextField("Breed", text: $viewModel.pet.breed)
            TextField("Age", text: $viewModel.pet.age)
            TextField("Weight", text: $viewModel.pet.weight)
            TextField("Notes", text: $viewModel.pet.notes, axis: .vertical)
                .lineLimit(3...6)
        }
        .navigationTitle("Pet Profile")
    }
}
