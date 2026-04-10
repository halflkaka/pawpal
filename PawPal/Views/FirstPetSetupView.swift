import SwiftUI

struct FirstPetSetupView: View {
    let user: AppUser
    let onComplete: (RemotePet) -> Void

    @StateObject private var petsService = PetsService()
    @State private var name = ""
    @State private var species = "Dog"
    @State private var breed = ""
    @State private var sex = ""
    @State private var age = ""
    @State private var weight = ""
    @State private var homeCity = ""
    @State private var bio = ""
    @State private var isSaving = false
    @State private var isCompleting = false
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

                    stepContent

                    bottomBar
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                        .padding(.top, 8)
                }

                if isCompleting {
                    completionOverlay
                }
            }
            .navigationBarBackButtonHidden(true)
        }
        .onAppear {
            updateFocus(for: currentStep)
        }
        .onChange(of: currentStep) { _, newValue in
            updateFocus(for: newValue)
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

                Text("\(currentStep + 1)/8")
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

    @ViewBuilder
    private var stepContent: some View {
        Group {
            switch currentStep {
            case 0:
                stepScaffold(
                    eyebrow: "Name",
                    title: "What's your pet's name?",
                    subtitle: "Start with the name you'll call them every day."
                ) {
                    refinedTextField(text: $name, placeholder: "Pet name")
                }
            case 1:
                stepScaffold(
                    eyebrow: "Species",
                    title: "What species are they?",
                    subtitle: "Choose the one that fits best."
                ) {
                    speciesPicker
                }
            case 2:
                stepScaffold(
                    eyebrow: "Breed",
                    title: "What's their breed?",
                    subtitle: "Optional, you can always change this later."
                ) {
                    refinedTextField(text: $breed, placeholder: "Breed")
                }
            case 3:
                stepScaffold(
                    eyebrow: "Sex",
                    title: "What should we show?",
                    subtitle: "Optional, just the simple label for now."
                ) {
                    sexPicker
                }
            case 4:
                stepScaffold(
                    eyebrow: "Age",
                    title: "How old are they?",
                    subtitle: "Optional, any format is fine."
                ) {
                    refinedTextField(text: $age, placeholder: "2 years")
                }
            case 5:
                stepScaffold(
                    eyebrow: "Weight",
                    title: "How much do they weigh?",
                    subtitle: "Optional, add a unit if you want."
                ) {
                    refinedTextField(text: $weight, placeholder: "12 lb")
                }
            case 6:
                stepScaffold(
                    eyebrow: "Home city",
                    title: "Where do they call home?",
                    subtitle: "Optional, just the city is enough."
                ) {
                    refinedTextField(text: $homeCity, placeholder: "San Francisco")
                }
            case 7:
                stepScaffold(
                    eyebrow: "Bio",
                    title: "How would you describe them?",
                    subtitle: "Optional, keep it short and warm."
                ) {
                    bioEditor
                }
            default:
                EmptyView()
            }
        }
        .contentShape(Rectangle())
        .gesture(stepSwipeGesture)
        .animation(.easeInOut(duration: 0.22), value: currentStep)
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
                        goBack()
                    } label: {
                        Text("Back")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 88, height: 52)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving || isCompleting)
                }

                Button {
                    advance()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(primaryButtonEnabled ? Color.black : Color(.tertiarySystemFill))
                            .frame(height: 52)

                        if isSaving || isCompleting {
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
                .disabled(!primaryButtonEnabled || isSaving || isCompleting)
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

    private var sexPicker: some View {
        HStack(spacing: 12) {
            ForEach(["", "Male", "Female"], id: \.self) { option in
                Button {
                    sex = option
                } label: {
                    Text(option.isEmpty ? "Not set" : option)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(sex == option ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(sex == option ? Color.black : Color(.systemBackground).opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var bioEditor: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.9))
                .shadow(color: Color.black.opacity(0.04), radius: 18, y: 8)

            TextEditor(text: $bio)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(minHeight: 180)
                .font(.system(size: 18))

            if bio.isEmpty {
                Text("A little intro")
                    .font(.system(size: 18))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 180)
    }

    private func refinedTextField(text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("", text: text)
                .font(.system(size: 34, weight: .semibold))
                .textInputAutocapitalization(.words)
                .foregroundStyle(.primary)
                .focused($isTextFieldFocused)
                .submitLabel(isLastStep ? .done : .next)
                .onSubmit {
                    advance()
                }

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

    private var completionOverlay: some View {
        ZStack {
            Color.black.opacity(0.08)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .tint(.secondary)

                Text("Opening your pet profile")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(Color(.systemBackground).opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var progressValue: CGFloat {
        CGFloat(currentStep + 1) / 8
    }

    private var isLastStep: Bool {
        currentStep == 7
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

    private var stepSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard !isSaving && !isCompleting else { return }

                if value.translation.width < -50 {
                    advance()
                } else if value.translation.width > 50 {
                    goBack()
                }
            }
    }

    private func updateFocus(for step: Int) {
        isTextFieldFocused = step == 0 || step == 2 || step == 4 || step == 5 || step == 6
    }

    private func advance() {
        guard !isSaving && !isCompleting else { return }

        if isLastStep {
            Task {
                await save()
            }
            return
        }

        if currentStep == 0 && !canSave {
            return
        }

        withAnimation {
            currentStep = min(currentStep + 1, 7)
        }
    }

    private func goBack() {
        guard !isSaving && !isCompleting, currentStep > 0 else { return }

        withAnimation {
            currentStep = max(currentStep - 1, 0)
        }
    }

    private func save() async {
        guard canSave, !isSaving, !isCompleting else { return }
        isSaving = true
        petsService.errorMessage = nil
        defer { isSaving = false }

        guard let pet = await petsService.addPet(
            for: user.id,
            name: name,
            species: species,
            breed: breed,
            sex: sex,
            age: age,
            weight: weight,
            homeCity: homeCity,
            bio: bio
        ) else {
            if petsService.errorMessage == nil {
                petsService.errorMessage = "Could not save your pet. Please try again."
            }
            return
        }

        isCompleting = true
        onComplete(pet)
    }
}

private struct SpeciesOption: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let accent: Color
}
