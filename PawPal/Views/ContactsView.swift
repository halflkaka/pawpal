import SwiftUI

struct ContactsView: View {
    @StateObject private var postsService = PostsService()
    @State private var selectedFilter = DiscoverFilter.all
    @State private var searchText = ""

    private var filteredPosts: [RemotePost] {
        postsService.feedPosts.filter { post in
            matchesFilter(post) && matchesSearch(post)
        }
    }

    private var featuredPosts: [RemotePost] {
        Array(filteredPosts.prefix(8))
    }

    private var trendingTopics: [DiscoverTopic] {
        let grouped = Dictionary(grouping: filteredPosts) { normalizedMood($0.mood) }

        return grouped
            .compactMap { mood, posts in
                guard let mood else { return nil }
                return DiscoverTopic(
                    title: "#\(mood)",
                    count: posts.count,
                    emoji: emoji(for: mood)
                )
            }
            .sorted {
                if $0.count == $1.count {
                    return $0.title < $1.title
                }
                return $0.count > $1.count
            }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                searchBar
                filterRow

                if postsService.isLoadingFeed && postsService.feedPosts.isEmpty {
                    loadingState
                } else if filteredPosts.isEmpty {
                    emptyState
                } else {
                    featuredSection
                    trendsSection
                    latestSection
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
        .refreshable {
            await postsService.loadFeed()
        }
        .task {
            if postsService.feedPosts.isEmpty {
                await postsService.loadFeed()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("发现 🔭")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
            Text("搜索真实宠物动态，看看现在大家都在晒什么")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索宠物名、文案、城市、心情…", text: $searchText)
                .font(.system(size: 14, weight: .semibold))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: PawPalTheme.shadow, radius: 10, y: 4)
    }

    private var filterRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(DiscoverFilter.allCases, id: \.self) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter.title)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(selectedFilter == filter ? .white : PawPalTheme.secondaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selectedFilter == filter ? PawPalTheme.orange : .white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            PawPalSectionTitle(title: searchText.isEmpty ? "宠物推荐" : "搜索结果", emoji: "✨")

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(featuredPosts, id: \.id) { post in
                        DiscoverPetCard(post: post)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            PawPalSectionTitle(title: "热门话题", emoji: "🔥")

            if trendingTopics.isEmpty {
                Text("发几条带心情标签的动态，这里就会热闹起来。")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                ForEach(Array(trendingTopics.enumerated()), id: \.element.id) { index, topic in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(PawPalTheme.orangeSoft)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(topic.title)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(PawPalTheme.primaryText)
                            Text("\(topic.count) 条动态")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(topic.emoji)
                            .font(.system(size: 22))
                    }
                    .pawPalCard()
                }
            }
        }
    }

    private var latestSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            PawPalSectionTitle(title: "最新动态", emoji: "🫶")

            ForEach(filteredPosts.prefix(12), id: \.id) { post in
                DiscoverPostRow(post: post)
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(PawPalTheme.cardSoft)
                    .frame(height: 110)
                    .redacted(reason: .placeholder)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("🐾")
                .font(.system(size: 48))
            Text(searchText.isEmpty ? "还没有可发现的动态" : "没有找到匹配结果")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
            Text(searchText.isEmpty ? "等大家发帖后，这里会自动变成真实的发现页。" : "试试搜宠物名、城市，或者切换一个分类。")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
    }

    private func matchesFilter(_ post: RemotePost) -> Bool {
        switch selectedFilter {
        case .all:
            return true
        case .dogs:
            return normalizedSpecies(post.pet?.species) == "dog"
        case .cats:
            return normalizedSpecies(post.pet?.species) == "cat"
        case .rabbits:
            return ["rabbit", "bunny"].contains(normalizedSpecies(post.pet?.species))
        case .birds:
            return normalizedSpecies(post.pet?.species) == "bird"
        }
    }

    private func matchesSearch(_ post: RemotePost) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }

        let fields = [
            post.pet?.name,
            post.pet?.species,
            post.pet?.breed,
            post.pet?.home_city,
            post.caption,
            post.mood
        ]
        .compactMap { $0?.lowercased() }

        return fields.contains { $0.contains(query) }
    }

    private func normalizedSpecies(_ species: String?) -> String {
        species?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private func normalizedMood(_ mood: String?) -> String? {
        guard let mood else { return nil }
        let trimmed = mood.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func emoji(for mood: String) -> String {
        let value = mood.lowercased()
        if value.contains("开心") || value.contains("happy") || value.contains("joy") { return "😄" }
        if value.contains("困") || value.contains("sleep") || value.contains("nap") { return "😴" }
        if value.contains("疯") || value.contains("play") || value.contains("run") { return "🌀" }
        if value.contains("吃") || value.contains("snack") || value.contains("treat") { return "🍖" }
        return "🐾"
    }
}

private enum DiscoverFilter: CaseIterable {
    case all
    case dogs
    case cats
    case rabbits
    case birds

    var title: String {
        switch self {
        case .all: return "全部"
        case .dogs: return "狗狗"
        case .cats: return "猫咪"
        case .rabbits: return "兔兔"
        case .birds: return "鸟类"
        }
    }
}

private struct DiscoverPetCard: View {
    let post: RemotePost

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(cardGradient)
                    .frame(width: 190, height: 148)

                if let url = post.imageURLs.first {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 190, height: 148)
                                .clipped()
                        default:
                            Text(speciesEmoji)
                                .font(.system(size: 54))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    Text(speciesEmoji)
                        .font(.system(size: 54))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(post.pet?.name ?? "未知宠物")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.primaryText)
                    .lineLimit(1)

                Text(metaText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    Label("\(post.likeCount)", systemImage: "heart.fill")
                    Label("\(post.commentCount)", systemImage: "message.fill")
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.orange)
            }
        }
        .frame(width: 190, alignment: .leading)
        .pawPalCard()
    }

    private var speciesEmoji: String {
        switch post.pet?.species?.lowercased() {
        case "dog": return "🐶"
        case "cat": return "🐱"
        case "rabbit", "bunny": return "🐰"
        case "bird": return "🦜"
        default: return "🐾"
        }
    }

    private var metaText: String {
        let pieces = [post.pet?.species, post.pet?.home_city, post.mood]
            .compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        return pieces.isEmpty ? post.caption : pieces.joined(separator: " · ")
    }

    private var cardGradient: LinearGradient {
        LinearGradient(
            colors: [PawPalTheme.orange.opacity(0.35), PawPalTheme.cardSoft],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct DiscoverPostRow: View {
    let post: RemotePost

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(PawPalTheme.cardSoft)
                    .frame(width: 54, height: 54)
                Text(speciesEmoji)
                    .font(.system(size: 28))
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(post.pet?.name ?? "未知宠物")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(PawPalTheme.primaryText)
                    if let mood = trimmed(post.mood) {
                        Text("#\(mood)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(PawPalTheme.orange)
                    }
                }

                Text(post.caption)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PawPalTheme.secondaryText)
                    .lineLimit(2)

                Text(footerText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let url = post.imageURLs.first {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipped()
                    default:
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(PawPalTheme.cardSoft)
                            .frame(width: 64, height: 64)
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(PawPalTheme.tertiaryText)
                            }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .pawPalCard()
    }

    private var speciesEmoji: String {
        switch post.pet?.species?.lowercased() {
        case "dog": return "🐶"
        case "cat": return "🐱"
        case "rabbit", "bunny": return "🐰"
        case "bird": return "🦜"
        default: return "🐾"
        }
    }

    private var footerText: String {
        let city = trimmed(post.pet?.home_city)
        let species = trimmed(post.pet?.species)
        let pieces = [city, species, "❤️ \(post.likeCount)", "💬 \(post.commentCount)"]
            .compactMap { $0 }
        return pieces.joined(separator: " · ")
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}

private struct DiscoverTopic: Identifiable {
    let id = UUID()
    let title: String
    let count: Int
    let emoji: String
}
