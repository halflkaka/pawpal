import SwiftUI

struct AuthView: View {
    @Bindable var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var isRegisterMode = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.orange.opacity(0.16), Color.pink.opacity(0.10), Color.white],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        Spacer(minLength: 40)

                        heroSection
                        authCard

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var heroSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.16))
                    .frame(width: 92, height: 92)
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 8) {
                Text("PetHealth")
                    .font(.system(size: 34, weight: .bold))
                Text("A pet moments app with care tools.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var authCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(isRegisterMode ? "Create your account" : "Welcome back")
                    .font(.title3.bold())
                Text(isRegisterMode ? "Start posting pet moments and building your pet space." : "Sign in to continue to your pets, moments, and feed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 14) {
                field(title: "Email") {
                    TextField("name@example.com", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                field(title: "Password") {
                    SecureField("Enter password", text: $password)
                }
            }

            if let errorMessage = authManager.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Button {
                Task {
                    if isRegisterMode {
                        await authManager.register(email: email, password: password)
                    } else {
                        await authManager.signIn(email: email, password: password)
                    }
                }
            } label: {
                HStack {
                    Spacer()
                    if authManager.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(isRegisterMode ? "Create Account" : "Sign In")
                            .font(.headline)
                    }
                    Spacer()
                }
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || authManager.isLoading)

            Button(isRegisterMode ? "Already have an account? Sign In" : "New here? Create an account") {
                isRegisterMode.toggle()
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
        .padding(22)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 18, x: 0, y: 8)
    }

    private func field<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}
