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
    @FocusState private var isTextFieldFocused: Bool

    private let speciesOptions: [SpeciesOption] = [
        .init(name: "Dog", icon: "dog", accent: Color(red: 0.33, green: 0.53, blue: 0.42)),
        .init(name: "Cat", icon: "cat", accent: Color(red: 0.48, green: 0.45, blue: 0.62)),
        .init(name: "Other", icon: "pawprint", accent: Color(red: 0.56, green: 0.50, blue: 0.42))
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.systemGroupedBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 24)
                        .padding(.top, 28)

                    TabView(selection: $currentStep) {
                        stepScaffold(
                            eyebrow: "Name",
                            title: "What's your pet's name?",
                            subtitle: "Start with the name you'll call them every day."
                        ) {
                            refinedTextField(text: $name, placeholder: "Pet name")
                        }
                        .tag(0)

                        stepScaffold(
                            eyebrow: "Species",
                            title: "What species are they?",
                            subtitle: "Choose the one that fits best."
                        ) {
                            speciesPicker
                        }
                        .tag(1)

                        stepScaffold(
                            eyebrow: "Breed",
                            title: "What's their breed?",
                            subtitle: "Optional, you can always change this later."
                        ) {
                            refinedTextField(text: $breed, placeholder: "Breed")
                        }
                        .tag(2)

                        stepScaffold(
                            eyebrow: "Age",
                            title: "How old are they?",
                            subtitle: "Optional, any format is fine."
                        ) {
                            refinedTextField(text: $age, placeholder: "2 years")
                        }
                        .tag(3)

                        stepScaffold(
                            eyebrow: "Weight",
                            title: "How much do they weigh?",
                            subtitle: "Optional, add a unit if you want."
                        ) {
                            refinedTextField(text: $weight, placeholder: "12 lb")
                        }
                        .tag(4)

                        stepScaffold(
                            eyebrow: "Notes",
                            title: "Anything else to remember?",
                            subtitle: "Optional notes for now."
                        ) {
                            notesEditor
                        }
                        .tag(5)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut(duration: 0.22), value: currentStep)
                    .onChange(of: currentStep) { _, newValue in
                        isTextFieldFocused = newValue != 1 && newValue != 5
                    }

                    bottomBar
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                        .padding(.top, 8)
                }
            }
            .navigationBarBackButtonHidden(true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 56, height: 56)

                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.gray)
                }

                Spacer()

                Text("\(currentStep + 1)/6")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Create your first pet")
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(-0.6)

                Text("A calm start for your pet profile")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            progressBar

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
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 88, height: 52)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
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
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(primaryButtonEnabled ? Color.black : Color(.tertiarySystemFill))
                            .frame(height: 52)

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
                .buttonStyle(.plain)
                .disabled(!primaryButtonEnabled || isSaving)
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color(.systemFill))
                    .frame(height: 6)

                Capsule(style: .continuous)
                    .fill(Color.black)
                    .frame(width: max(28, geometry.size.width * progressValue), height: 6)
            }
        }
        .frame(height: 6)
    }

    private var speciesPicker: some View {
        HStack(spacing: 14) {
            ForEach(speciesOptions) { option in
                Button {
                    species = option.name
                } label: {
                    VStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(species == option.name ? option.accent.opacity(0.18) : Color(.secondarySystemBackground))
                                .frame(height: 112)

                            Image(systemName: option.icon)
                                .font(.system(size: 34, weight: .medium))
                                .foregroundStyle(species == option.name ? option.accent : Color(.secondaryLabel))
                        }

                        Text(option.name)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground).opacity(species == option.name ? 0.92 : 0.72))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(species == option.name ? option.accent.opacity(0.65) : Color.black.opacity(0.05), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: Color.black.opacity(species == option.name ? 0.08 : 0.03), radius: species == option.name ? 16 : 8, y: 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var notesEditor: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.9))
                .shadow(color: Color.black.opacity(0.04), radius: 18, y: 8)

            TextEditor(text: $notes)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(minHeight: 220)
                .font(.system(size: 18))

            if notes.isEmpty {
                Text("Notes")
                    .font(.system(size: 18))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 220)
    }

    private func refinedTextField(text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("", text: text)
                .font(.system(size: 34, weight: .semibold))
                .textInputAutocapitalization(.words)
                .foregroundStyle(.primary)
                .focused($isTextFieldFocused)

            Rectangle()
                .fill(Color.black.opacity(0.12))
                .frame(height: 1)
        }
        .overlay(alignment: .leading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
            }
        }
        .padding(.top, 20)
    }

    private func stepScaffold<Content: View>(eyebrow: String, title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 18)

            Text(eyebrow.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 18)

            Text(title)
                .font(.system(size: 38, weight: .semibold))
                .tracking(-0.9)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .padding(.top, 12)

            content()
                .padding(.top, 36)

            Spacer()
        }
        .padding(.horizontal, 24)
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
        .background(Color(.systemBackground).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var progressValue: CGFloat {
        CGFloat(currentStep + 1) / 6
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

private struct SpeciesOption: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let accent: Color
}
