import SwiftUI

struct AuthView: View {
    @Bindable var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var isRegisterMode = false
    @FocusState private var focusedField: Field?

    var body: some View {
        ZStack {
            PawPalBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 64)

                    // MARK: Brand mark
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [PawPalTheme.orange, PawPalTheme.orangeSoft],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 90, height: 90)
                                .shadow(color: PawPalTheme.orange.opacity(0.38), radius: 22, y: 10)
                            Text("🐾")
                                .font(.system(size: 42))
                        }

                        Text("PawPal")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(PawPalTheme.primaryText)

                        Text("让每一只宠物都闪闪发光 ✨")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(PawPalTheme.tertiaryText)
                    }
                    .padding(.bottom, 40)

                    // MARK: Mode switcher
                    HStack(spacing: 0) {
                        modeTab("登录", selected: !isRegisterMode) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isRegisterMode = false
                                authManager.clearError()
                                password = ""
                            }
                        }
                        modeTab("注册", selected: isRegisterMode) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isRegisterMode = true
                                authManager.clearError()
                                password = ""
                            }
                        }
                    }
                    .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                    // MARK: Fields
                    VStack(spacing: 0) {
                        authField("邮箱", text: $email, isSecure: false, field: .email)
                        Divider()
                            .padding(.horizontal, 16)
                        authField(
                            isRegisterMode ? "设置密码" : "密码",
                            text: $password,
                            isSecure: true,
                            field: .password
                        )
                    }
                    .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: PawPalTheme.shadow, radius: 22, y: 8)
                    .padding(.horizontal, 24)

                    // MARK: Feedback
                    if let error = authManager.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 28)
                        .padding(.top, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // MARK: CTA
                    Button {
                        submit()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(buttonEnabled
                                      ? LinearGradient(colors: [PawPalTheme.orange, PawPalTheme.orangeSoft], startPoint: .leading, endPoint: .trailing)
                                      : LinearGradient(colors: [Color(.tertiarySystemFill), Color(.tertiarySystemFill)], startPoint: .leading, endPoint: .trailing)
                                )
                                .frame(height: 56)
                                .shadow(color: buttonEnabled ? PawPalTheme.orange.opacity(0.42) : .clear, radius: 18, y: 8)

                            if authManager.isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text(isRegisterMode ? "创建账号" : "登录")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(buttonEnabled ? .white : .secondary)
                            }
                        }
                    }
                    .disabled(!buttonEnabled)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .animation(.easeInOut(duration: 0.15), value: buttonEnabled)

                    Spacer(minLength: 48)
                }
            }
            .scrollIndicators(.hidden)
        }
        .animation(.easeInOut(duration: 0.2), value: authManager.errorMessage)
        .onAppear { focusedField = .email }
        .onChange(of: email) { _, _ in authManager.clearError() }
        .onChange(of: password) { _, _ in authManager.clearError() }
        .onChange(of: authManager.currentUser?.id) { _, newValue in
            if newValue != nil { focusedField = nil }
        }
    }

    // MARK: - Subviews

    private func modeTab(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? .white : PawPalTheme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    selected
                        ? AnyShapeStyle(LinearGradient(colors: [PawPalTheme.orange, PawPalTheme.orangeSoft], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Color.clear),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .padding(3)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: selected)
    }

    private func authField(_ placeholder: String, text: Binding<String>, isSecure: Bool, field: Field) -> some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: text)
                    .textContentType(isRegisterMode ? .newPassword : .password)
            } else {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textContentType(.username)
            }
        }
        .font(.system(size: 16))
        .submitLabel(field == .email ? .next : .go)
        .focused($focusedField, equals: field)
        .onSubmit {
            if field == .email { focusedField = .password } else { submit() }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    // MARK: - Helpers

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

    private enum Field { case email, password }
}
