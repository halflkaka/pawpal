import SwiftUI

struct AuthView: View {
    @Bindable var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var isRegisterMode = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Spacer()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Welcome")
                        .font(.largeTitle.bold())
                    Text("Sign in to PetHealth to follow pets, post moments, and build your pet space.")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }

                if let errorMessage = authManager.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
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
                    .padding()
                }
                .buttonStyle(.borderedProminent)

                Button(isRegisterMode ? "Already have an account? Sign In" : "Need an account? Register") {
                    isRegisterMode.toggle()
                }
                .font(.subheadline)

                Spacer()
            }
            .padding(24)
            .navigationBarHidden(true)
        }
    }
}
