import SwiftUI

struct ContactsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(sampleContacts) { contact in
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                                .frame(width: 48, height: 48)
                                .overlay {
                                    Image(systemName: contact.icon)
                                        .foregroundStyle(.gray)
                                }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(contact.name)
                                    .font(.system(size: 16, weight: .medium))
                                Text(contact.note)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        Divider()
                            .padding(.leading, 76)
                    }
                    .background(Color(.systemBackground))
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Contacts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ContactPreview: Identifiable {
    let id = UUID()
    let name: String
    let note: String
    let icon: String
}

private let sampleContacts: [ContactPreview] = [
    .init(name: "Mochi", note: "Golden Retriever", icon: "dog.fill"),
    .init(name: "Luna", note: "British Shorthair", icon: "cat.fill")
]
