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
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: 76, height: 76)
                            .overlay {
                                Image(systemName: "pawprint.fill")
                                    .font(.system(size: 28, weight: .medium))
                                    .foregroundStyle(.gray)
                            }

                        Text("PawPal")
                            .font(.system(size: 30, weight: .semibold))
                            .tracking(-0.5)

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
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 16)

                    if let errorMessage = authManager.errorMessage {
                        feedbackCard(icon: "exclamationmark.circle", text: errorMessage, tint: .red)
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                    }

                    if authManager.isLoading && authManager.errorMessage == nil {
                        feedbackCard(icon: nil, text: isRegisterMode ? "Creating account" : "Signing in", tint: .secondary, showsProgress: true)
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                    }

                    Button {
                        submit()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(buttonEnabled ? Color.black : Color(.tertiarySystemFill))
                                .frame(height: 52)

                            if authManager.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(isRegisterMode ? "Create Account" : "Sign In")
                                    .font(.system(size: 17, weight: .semibold))
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
                    .font(.system(size: 15, weight: .medium))
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

    private enum Field {
        case email
        case password
    }
}
