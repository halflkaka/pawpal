import SwiftUI

struct AuthView: View {
    @Bindable var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var isRegisterMode = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: 32)

                    VStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: 72, height: 72)
                            .overlay {
                                Image(systemName: "pawprint.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.gray)
                            }

                        Text("PetHealth")
                            .font(.system(size: 28, weight: .semibold))
                    }
                    .padding(.bottom, 28)

                    VStack(spacing: 0) {
                        inputRow(title: "Email") {
                            TextField("name@example.com", text: $email)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        Divider().padding(.leading, 16)

                        inputRow(title: "Password") {
                            SecureField("Enter password", text: $password)
                        }
                    }
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)

                    if let errorMessage = authManager.errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
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
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(buttonEnabled ? Color.green : Color(.tertiarySystemFill))
                                .frame(height: 50)

                            if authManager.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(isRegisterMode ? "Create Account" : "Sign In")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(buttonEnabled ? .white : .secondary)
                            }
                        }
                    }
                    .disabled(!buttonEnabled || authManager.isLoading)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)

                    Button(isRegisterMode ? "Sign In" : "Create Account") {
                        isRegisterMode.toggle()
                        authManager.clearError()
                    }
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .padding(.top, 18)

                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
        .onChange(of: email) { _, _ in authManager.clearError() }
        .onChange(of: password) { _, _ in authManager.clearError() }
    }

    private var buttonEnabled: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private func inputRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)

            content()
                .font(.system(size: 16))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}
