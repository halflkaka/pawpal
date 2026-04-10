import SwiftUI
import SwiftData

struct FeedView: View {
    @Query(sort: \StoredPost.createdAt, order: .reverse) private var posts: [StoredPost]
    @State private var selectedStoryID: UUID?

    private let stories = PawPalStory.sample

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header
                storiesRow
                composerCard

                if posts.isEmpty {
                    ForEach(PawPalFeedPost.sample) { post in
                        samplePostCard(post)
                    }
                } else {
                    ForEach(posts) { post in
                        storedPostCard(post)
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("🐾 PawPal")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.primaryText)
                Text("Moments from your favorite chaos gremlins")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.tertiaryText)
            }

            Spacer()

            headerButton(systemImage: "magnifyingglass")
            headerButton(systemImage: "bell.fill", badge: true)
        }
    }

    private var storiesRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(stories) { story in
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(storyRingFill(for: story))
                                .frame(width: 62, height: 62)

                            PawPalAvatar(
                                emoji: story.emoji,
                                size: 56,
                                background: PawPalTheme.background,
                                ringColor: story.isAdd ? PawPalTheme.orangeSoft : PawPalTheme.background
                            )
                        }

                        Text(story.name)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(PawPalTheme.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(width: 64)
                    .onTapGesture {
                        selectedStoryID = story.id
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var composerCard: some View {
        HStack(spacing: 12) {
            PawPalAvatar(emoji: "🐶", ringColor: PawPalTheme.orangeSoft)

            VStack(alignment: .leading, spacing: 4) {
                Text("Share a moment")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.primaryText)
                Text("Photo, story, or tiny chaos update 🐾")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            NavigationLink {
                CreatePostView()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(PawPalTheme.orange, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .pawPalCard()
    }

    private func samplePostCard(_ post: PawPalFeedPost) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PawPalAvatar(emoji: post.avatarEmoji, size: 44, ringColor: PawPalTheme.orangeSoft)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(post.name)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(PawPalTheme.primaryText)
                        PawPalPill(text: post.badge, systemImage: nil, tint: PawPalTheme.green)
                    }

                    Text("\(post.owner) · \(post.time)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
            }

            Text(post.text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PawPalTheme.primaryText)
                .lineSpacing(3)

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(post.background)
                    .frame(height: 220)
                    .overlay {
                        Text(post.imageEmoji)
                            .font(.system(size: 72))
                    }

                PawPalPill(text: post.location, systemImage: "mappin.and.ellipse", tint: PawPalTheme.secondaryText)
                    .padding(12)
            }

            if !post.tags.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(post.tags, id: \.self) { tag in
                            PawPalPill(text: tag, systemImage: nil, tint: PawPalTheme.orange)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            HStack(spacing: 10) {
                reactionButton(icon: "heart", text: "\(post.likes)")
                reactionButton(icon: "message", text: "\(post.comments)")
                reactionButton(icon: "pawprint.fill", text: "Boop")
                Spacer()
                reactionButton(icon: "paperplane", text: "")
            }
        }
        .pawPalCard()
    }

    private func storedPostCard(_ post: StoredPost) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PawPalAvatar(emoji: "🐾", size: 44, ringColor: PawPalTheme.orangeSoft)

                VStack(alignment: .leading, spacing: 4) {
                    Text(post.petName.isEmpty ? "Pet" : post.petName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(PawPalTheme.primaryText)
                    Text(post.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if !post.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(post.caption)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PawPalTheme.primaryText)
                    .lineSpacing(3)
            }

            if !post.imageDataList.isEmpty {
                imageGrid(post.imageDataList)
            }

            if !post.mood.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                PawPalPill(text: post.mood, systemImage: "sparkles", tint: PawPalTheme.orangeSoft)
            }
        }
        .pawPalCard()
    }

    private func headerButton(systemImage: String, badge: Bool = false) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(PawPalTheme.primaryText)
                .frame(width: 38, height: 38)
                .background(.white, in: Circle())
                .shadow(color: PawPalTheme.shadow, radius: 8, y: 4)

            if badge {
                Circle()
                    .fill(Color.red)
                    .frame(width: 9, height: 9)
                    .offset(x: -2, y: 2)
            }
        }
    }

    private func storyRingFill(for story: PawPalStory) -> LinearGradient {
        if story.isAdd {
            return LinearGradient(colors: [.white, .white], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        if story.seen {
            return LinearGradient(colors: [Color.gray.opacity(0.22), Color.gray.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(
            colors: [PawPalTheme.orange, PawPalTheme.orangeSoft, PawPalTheme.yellow],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func reactionButton(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            if !text.isEmpty {
                Text(text)
            }
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(PawPalTheme.secondaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(PawPalTheme.background, in: Capsule())
    }

    private func imageGrid(_ images: [Data]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: min(images.count == 1 ? 1 : 3, 3))

        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(images.enumerated()), id: \.offset) { _, data in
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: images.count == 1 ? 220 : 100)
                        .frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: 18))
                }
            }
        }
    }
}

private struct PawPalStory: Identifiable {
    let id = UUID()
    let name: String
    let emoji: String
    let seen: Bool
    let isAdd: Bool

    static let sample: [PawPalStory] = [
        .init(name: "You", emoji: "➕", seen: false, isAdd: true),
        .init(name: "Mochi", emoji: "🐶", seen: false, isAdd: false),
        .init(name: "Noodle", emoji: "🐰", seen: false, isAdd: false),
        .init(name: "Luna", emoji: "🐱", seen: true, isAdd: false),
        .init(name: "Waffles", emoji: "🦜", seen: true, isAdd: false)
    ]
}

private struct PawPalFeedPost: Identifiable {
    let id: Int
    let avatarEmoji: String
    let name: String
    let badge: String
    let owner: String
    let time: String
    let text: String
    let imageEmoji: String
    let background: LinearGradient
    let location: String
    let tags: [String]
    let likes: Int
    let comments: Int

    static let sample: [PawPalFeedPost] = [
        .init(
            id: 1,
            avatarEmoji: "🐶",
            name: "Mochi",
            badge: "Shiba",
            owner: "@sakura",
            time: "2m",
            text: "Finally nailed the give-paw trick. Three weeks of training paid off 🐾",
            imageEmoji: "🐕",
            background: LinearGradient(colors: [Color(red: 1.0, green: 0.88, blue: 0.70), Color(red: 1.0, green: 0.80, blue: 0.50)], startPoint: .topLeading, endPoint: .bottomTrailing),
            location: "Riverside Park",
            tags: ["#PawProgress", "#ShibaInu"],
            likes: 284,
            comments: 42
        ),
        .init(
            id: 2,
            avatarEmoji: "🐱",
            name: "Luna",
            badge: "Maine Coon",
            owner: "@felix",
            time: "1h",
            text: "My kingdom. You may not enter 📦👑",
            imageEmoji: "📦",
            background: LinearGradient(colors: [Color(red: 0.72, green: 0.87, blue: 0.94), Color(red: 0.83, green: 0.72, blue: 0.94)], startPoint: .topLeading, endPoint: .bottomTrailing),
            location: "Sunny window",
            tags: ["#CatLife", "#BoxEnjoyer"],
            likes: 531,
            comments: 88
        )
    ]
}
