import SwiftUI

struct ChatListView: View {
    @State private var searchText = ""

    private var filteredChats: [ChatPreview] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sampleChats }
        return sampleChats.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) ||
            $0.preview.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            Divider()
            chatList
        }
        .background(Color(.systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Chats")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)

            Spacer()

            Button {
                // new chat action
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PawPalTheme.orange)
                    .frame(width: 36, height: 36)
                    .background(PawPalTheme.orange.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            TextField("Search", text: $searchText)
                .font(.system(size: 14))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Chat list (flat rows with dividers, no cards)

    private var chatList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(filteredChats.enumerated()), id: \.element.id) { index, chat in
                    chatRow(chat)
                    if index < filteredChats.count - 1 {
                        Divider()
                            .padding(.leading, 82)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func chatRow(_ chat: ChatPreview) -> some View {
        HStack(spacing: 14) {
            // Avatar with optional online indicator
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .fill(PawPalTheme.cardSoft)
                        .frame(width: 52, height: 52)
                    Text(chat.emoji)
                        .font(.system(size: 26))
                }
                if chat.online {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        .offset(x: 1, y: 1)
                }
            }

            // Name + preview
            VStack(alignment: .leading, spacing: 4) {
                Text(chat.name)
                    .font(.system(size: 15, weight: chat.unreadCount > 0 ? .bold : .semibold))
                    .foregroundStyle(PawPalTheme.primaryText)
                    .lineLimit(1)

                Text(chat.preview)
                    .font(.system(size: 13, weight: chat.unreadCount > 0 ? .semibold : .regular))
                    .foregroundStyle(chat.unreadCount > 0 ? PawPalTheme.primaryText.opacity(0.65) : .secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Time + unread badge
            VStack(alignment: .trailing, spacing: 6) {
                Text(chat.time)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if chat.unreadCount > 0 {
                    Text("\(chat.unreadCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .padding(.horizontal, 5)
                        .background(PawPalTheme.orange, in: Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
    }
}

// MARK: - Models

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
    .init(emoji: "🐕", name: "Biscuit's Dad",  preview: "Playdate tomorrow?? 🐾",         time: "now", unreadCount: 3,  online: true),
    .init(emoji: "🐱", name: "Luna Fan Club",   preview: "She's so fluffy omg 😭",          time: "2m",  unreadCount: 12, online: false),
    .init(emoji: "🏥", name: "Dr. Park",        preview: "Mochi's checkup is next Tuesday", time: "1h",  unreadCount: 0,  online: true),
    .init(emoji: "🐇", name: "Noodle",          preview: "Binkied 4 times today lol",       time: "3h",  unreadCount: 1,  online: false),
    .init(emoji: "🐩", name: "Poodle Gang NYC", preview: "Anyone free Saturday morning?",   time: "5h",  unreadCount: 0,  online: false),
]
