import SwiftUI

struct ProfileView: View {
    let user: AppUser
    @Bindable var authManager: AuthManager

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                profileHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 18)

                VStack(spacing: 0) {
                    profileRow(title: "Display Name", value: user.displayName ?? fallbackName)
                    Divider().padding(.leading, 16)
                    profileRow(title: "Email", value: user.email ?? "")
                }
                .background(Color(.systemBackground))

                VStack(spacing: 0) {
                    Button {
                        authManager.signOut()
                    } label: {
                        HStack {
                            Text("Sign Out")
                                .foregroundStyle(.red)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color(.systemBackground))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 28)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Me")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var profileHeader: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.gray)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(user.displayName ?? fallbackName)
                    .font(.system(size: 22, weight: .semibold))
                if let email = user.email {
                    Text(email)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    private func profileRow(title: String, value: String) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .foregroundStyle(.primary)

            Spacer()
        }
        .font(.system(size: 16))
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private var fallbackName: String {
        user.email?.components(separatedBy: "@").first ?? "User"
    }
}
