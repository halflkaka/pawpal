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
    @State private var currentStep = 0

    private let speciesOptions = ["Dog", "Cat", "Other"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    TabView(selection: $currentStep) {
                        stepCard(
                            title: "What's your pet's name?",
                            subtitle: "Start with the name you'll call them every day."
                        ) {
                            textEntryCard(text: $name, placeholder: "Pet name")
                        }
                        .tag(0)

                        stepCard(
                            title: "What species is your pet?",
                            subtitle: "Pick the one that fits best."
                        ) {
                            speciesCard
                        }
                        .tag(1)

                        stepCard(
                            title: "What's their breed?",
                            subtitle: "Optional, you can update it later."
                        ) {
                            textEntryCard(text: $breed, placeholder: "Breed")
                        }
                        .tag(2)

                        stepCard(
                            title: "How old are they?",
                            subtitle: "Optional, use any format you like."
                        ) {
                            textEntryCard(text: $age, placeholder: "2 years")
                        }
                        .tag(3)

                        stepCard(
                            title: "How much do they weigh?",
                            subtitle: "Optional, you can add a unit if you want."
                        ) {
                            textEntryCard(text: $weight, placeholder: "12 lb")
                        }
                        .tag(4)

                        stepCard(
                            title: "Anything else to remember?",
                            subtitle: "Optional notes for now."
                        ) {
                            notesCard
                        }
                        .tag(5)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut(duration: 0.2), value: currentStep)

                    VStack(spacing: 12) {
                        progressDots

                        if let errorMessage = petsService.errorMessage {
                            feedbackCard(icon: "exclamationmark.circle", text: errorMessage, tint: .red)
                        }

                        if isSaving && petsService.errorMessage == nil {
                            feedbackCard(icon: nil, text: "Finishing setup", tint: .secondary, showsProgress: true)
                        }

                        HStack(spacing: 12) {
                            if currentStep > 0 {
                                Button {
                                    withAnimation {
                                        currentStep -= 1
                                    }
                                } label: {
                                    Text("Back")
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 54)
                                        .background(Color(.secondarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                            }

                            Button {
                                if isLastStep {
                                    Task {
                                        await save()
                                    }
                                } else {
                                    withAnimation {
                                        currentStep += 1
                                    }
                                }
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(primaryButtonEnabled ? Color.green : Color(.tertiarySystemFill))
                                        .frame(height: 54)

                                    if isSaving {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Text(isLastStep ? "Finish" : "Next")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(primaryButtonEnabled ? .white : .secondary)
                                    }
                                }
                            }
                            .disabled(!primaryButtonEnabled || isSaving)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarBackButtonHidden(true)
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .frame(width: 76, height: 76)
                .overlay {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.gray)
                }

            VStack(spacing: 6) {
                Text("Create your first pet")
                    .font(.system(size: 28, weight: .semibold))

                Text("This will be your active pet")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == currentStep ? Color.primary : Color(.systemFill))
                    .frame(width: index == currentStep ? 20 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: currentStep)
            }
        }
        .padding(.top, 12)
    }

    private var speciesCard: some View {
        VStack(spacing: 12) {
            ForEach(speciesOptions, id: \.self) { option in
                Button {
                    species = option
                } label: {
                    HStack {
                        Text(option)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.primary)

                        Spacer()

                        Image(systemName: species == option ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(species == option ? Color.green : Color(.systemGray3))
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 60)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var notesCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            TextEditor(text: $notes)
                .scrollContentBackground(.hidden)
                .padding(18)
                .frame(minHeight: 180)
                .font(.system(size: 17))

            if notes.isEmpty {
                Text("Notes")
                    .font(.system(size: 17))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 30)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
    }

    private func textEntryCard(text: Binding<String>, placeholder: String) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            TextField("", text: text)
                .font(.system(size: 30, weight: .semibold))
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 24)

            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 24)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 120)
    }

    private func stepCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }

            content()

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private func feedbackCard(icon: String?, text: String, tint: Color, showsProgress: Bool = false) -> some View {
        HStack(spacing: 10) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else if let icon {
                Image(systemName: icon)
                    .foregroundStyle(tint)
            }

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var isLastStep: Bool {
        currentStep == 5
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var primaryButtonEnabled: Bool {
        if isLastStep {
            return canSave
        }
        return currentStep != 0 || canSave
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        petsService.errorMessage = nil
        defer { isSaving = false }

        guard let pet = await petsService.addPet(
            for: user.id,
            name: name,
            species: species,
            breed: breed,
            age: age,
            weight: weight,
            notes: notes
        ) else {
            if petsService.errorMessage == nil {
                petsService.errorMessage = "Could not save your pet. Please try again."
            }
            return
        }

        onComplete(pet)
    }
}
