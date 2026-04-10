import SwiftUI

struct ChatListView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(sampleChats) { chat in
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                                .frame(width: 52, height: 52)
                                .overlay {
                                    Image(systemName: chat.icon)
                                        .foregroundStyle(.gray)
                                }

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(chat.name)
                                        .font(.system(size: 16, weight: .medium))
                                    Spacer()
                                    Text(chat.time)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }

                                Text(chat.preview)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        Divider()
                            .padding(.leading, 80)
                    }
                    .background(Color(.systemBackground))
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ChatPreview: Identifiable {
    let id = UUID()
    let name: String
    let preview: String
    let time: String
    let icon: String
}

private let sampleChats: [ChatPreview] = [
    .init(name: "Mochi", preview: "Went to the park today", time: "2:18 PM", icon: "dog.fill"),
    .init(name: "Luna", preview: "Just posted new photos", time: "Yesterday", icon: "cat.fill")
]
