import SwiftUI

struct AuthView: View {
    @Bindable var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var isRegisterMode = false
    @FocusState private var focusedField: Field?

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

                        Text(isRegisterMode ? "Set up your account" : "Sign in to continue")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 28)

                    VStack(spacing: 0) {
                        inputRow(title: "Email") {
                            TextField("name@example.com", text: $email)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .textContentType(.username)
                                .submitLabel(.next)
                                .focused($focusedField, equals: .email)
                                .onSubmit {
                                    focusedField = .password
                                }
                        }

                        Divider().padding(.leading, 16)

                        inputRow(title: "Password") {
                            SecureField("Enter password", text: $password)
                                .textContentType(isRegisterMode ? .newPassword : .password)
                                .submitLabel(.go)
                                .focused($focusedField, equals: .password)
                                .onSubmit {
                                    submit()
                                }
                        }
                    }
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)

                    if let errorMessage = authManager.errorMessage {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    }

                    if authManager.isLoading && authManager.errorMessage == nil {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text(isRegisterMode ? "Creating account" : "Signing in")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    }

                    Button {
                        submit()
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
                    .disabled(!buttonEnabled)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)

                    Button(isRegisterMode ? "Sign In Instead" : "Create Account Instead") {
                        isRegisterMode.toggle()
                        authManager.clearError()
                        password = ""
                        focusedField = .email
                    }
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .padding(.top, 18)
                    .disabled(authManager.isLoading)

                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            focusedField = .email
        }
        .onChange(of: email) { _, _ in
            authManager.clearError()
        }
        .onChange(of: password) { _, _ in
            authManager.clearError()
        }
        .onChange(of: authManager.currentUser?.id) { _, newValue in
            if newValue != nil {
                focusedField = nil
            }
        }
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var buttonEnabled: Bool {
        !normalizedEmail.isEmpty && !password.isEmpty && !authManager.isLoading
    }

    private func submit() {
        guard buttonEnabled else { return }

        focusedField = nil
        authManager.clearError()

        Task {
            if isRegisterMode {
                await authManager.register(email: normalizedEmail, password: password)
            } else {
                await authManager.signIn(email: normalizedEmail, password: password)
            }
        }
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

    private enum Field {
        case email
        case password
    }
}
