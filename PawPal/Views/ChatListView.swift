import SwiftUI

struct ChatListView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                searchBar

                VStack(spacing: 10) {
                    ForEach(sampleChats) { chat in
                        chatRow(chat)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(PawPalBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Chats 💬")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.primaryText)
                Text("Playdates, gossip, and vet reminders")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.tertiaryText)
            }

            Spacer()

            Image(systemName: "square.and.pencil")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(PawPalTheme.orange, in: Circle())
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
            Text("Search conversations")
            Spacer()
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(red: 0.48, green: 0.31, blue: 0.18).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func chatRow(_ chat: ChatPreview) -> some View {
        HStack(spacing: 12) {
            PawPalAvatar(emoji: chat.emoji, size: 54)
                .overlay(alignment: .bottomTrailing) {
                    if chat.online {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 13, height: 13)
                            .overlay {
                                Circle().stroke(PawPalTheme.background, lineWidth: 2)
                            }
                            .offset(x: 1, y: 1)
                    }
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(chat.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.primaryText)

                Text(chat.preview)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(chat.time)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                if chat.unreadCount > 0 {
                    Text("\(chat.unreadCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .padding(.horizontal, 4)
                        .background(PawPalTheme.orange, in: Capsule())
                }
            }
        }
        .pawPalCard()
    }
}

private struct ChatPreview: Identifiable {
    let id = UUID()
    let emoji: String
    let name: String
    let preview: String
    let time: String
    let unreadCount: Int
    let online: Bool
}

private let sampleChats: [ChatPreview] = [
    .init(emoji: "🐕", name: "Biscuit’s Dad", preview: "Playdate tomorrow?? 🐾", time: "now", unreadCount: 3, online: true),
    .init(emoji: "🐱", name: "Luna Fan Club", preview: "She’s so fluffy omg 😭", time: "2m", unreadCount: 12, online: false),
    .init(emoji: "🏥", name: "Dr. Park", preview: "Mochi’s checkup is next Tue", time: "1h", unreadCount: 0, online: true),
    .init(emoji: "🐇", name: "Noodle", preview: "Binkied 4 times today lol", time: "3h", unreadCount: 1, online: false)
]
