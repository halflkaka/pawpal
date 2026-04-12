import SwiftUI

struct ContactsView: View {
    @StateObject private var postsService = PostsService()
    @StateObject private var petsService = PetsService()
    @State private var discoverTab: DiscoverTab = .posts
    @State private var selectedFilter = DiscoverFilter.all
    @State private var searchText = ""
    @State private var petSpeciesFilter = "all"

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
                tabSwitcher

                if discoverTab == .posts {
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
                } else {
                    petSpeciesRow
                    petsContent
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
        .navigationDestination(for: RemotePet.self) { pet in
            PetProfileView(pet: pet)
        }
        .refreshable {
            if discoverTab == .posts {
                await postsService.loadFeed()
            } else {
                await petsService.loadAllPets()
            }
        }
        .task {
            if postsService.feedPosts.isEmpty {
                await postsService.loadFeed()
            }
        }
        .onChange(of: discoverTab) { _, tab in
            if tab == .pets && petsService.allPets.isEmpty && !petsService.isLoadingAll {
                Task { await petsService.loadAllPets() }
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

    // MARK: - Tab switcher

    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            ForEach([DiscoverTab.posts, DiscoverTab.pets], id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        discoverTab = tab
                    }
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: .bold))
                            Text(tab.title)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(discoverTab == tab ? PawPalTheme.orange : PawPalTheme.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)

                        Rectangle()
                            .fill(discoverTab == tab ? PawPalTheme.orange : Color.clear)
                            .frame(height: 2)
                            .clipShape(Capsule())
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: PawPalTheme.shadow, radius: 8, y: 3)
    }

    // MARK: - Pets tab

    private var filteredPets: [RemotePet] {
        guard petSpeciesFilter != "all" else { return petsService.allPets }
        return petsService.allPets.filter {
            $0.species?.lowercased() == petSpeciesFilter.lowercased()
        }
    }

    private var petSpeciesRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(PetSpeciesFilter.allCases, id: \.self) { filter in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            petSpeciesFilter = filter.rawValue
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(filter.emoji)
                            Text(filter.label)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(petSpeciesFilter == filter.rawValue ? .white : PawPalTheme.secondaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            petSpeciesFilter == filter.rawValue ? PawPalTheme.orange : .white,
                            in: Capsule()
                        )
                        .shadow(
                            color: petSpeciesFilter == filter.rawValue ? PawPalTheme.orange.opacity(0.3) : PawPalTheme.softShadow,
                            radius: 6, y: 3
                        )
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: petSpeciesFilter == filter.rawValue)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private var petsContent: some View {
        Group {
            if petsService.isLoadingAll && petsService.allPets.isEmpty {
                petsLoadingState
            } else if let error = petsService.errorMessage, petsService.allPets.isEmpty {
                VStack(spacing: 12) {
                    Text("⚠️")
                        .font(.system(size: 40))
                    Text(error)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 48)
                .padding(.horizontal, 32)
            } else if filteredPets.isEmpty {
                petsEmptyState
            } else {
                petsGrid
            }
        }
    }

    private var petsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ForEach(filteredPets) { pet in
                NavigationLink(value: pet) {
                    PetDiscoverCard(pet: pet)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var petsLoadingState: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(PawPalTheme.cardSoft)
                    .frame(height: 160)
                    .redacted(reason: .placeholder)
            }
        }
    }

    private var petsEmptyState: some View {
        VStack(spacing: 14) {
            Text("🐾")
                .font(.system(size: 48))
            Text(petSpeciesFilter == "all" ? "还没有宠物档案" : "没有找到这类宠物")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
            Text("快去发帖让你的宠物出现在这里吧！")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.bottom, 40)
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

private enum DiscoverTab: Hashable {
    case posts
    case pets

    var title: String {
        switch self {
        case .posts: return "动态"
        case .pets:  return "宠物"
        }
    }

    var icon: String {
        switch self {
        case .posts: return "square.stack.fill"
        case .pets:  return "pawprint.fill"
        }
    }
}

private enum PetSpeciesFilter: String, CaseIterable {
    case all, dog, cat, rabbit, bird, hamster

    var label: String {
        switch self {
        case .all:     return "全部"
        case .dog:     return "狗狗"
        case .cat:     return "猫咪"
        case .rabbit:  return "兔兔"
        case .bird:    return "鸟类"
        case .hamster: return "仓鼠"
        }
    }

    var emoji: String {
        switch self {
        case .all:     return "🐾"
        case .dog:     return "🐶"
        case .cat:     return "🐱"
        case .rabbit:  return "🐰"
        case .bird:    return "🦜"
        case .hamster: return "🐹"
        }
    }
}

private struct PetDiscoverCard: View {
    let pet: RemotePet

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Avatar / emoji
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(
                        colors: [PawPalTheme.orange.opacity(0.25), PawPalTheme.cardSoft],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(maxWidth: .infinity)
                    .frame(height: 110)
                Text(speciesEmoji)
                    .font(.system(size: 52))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(pet.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.primaryText)
                    .lineLimit(1)

                if let meta = metaLine, !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PawPalTheme.secondaryText)
                        .lineLimit(1)
                }

                if let city = trimmed(pet.home_city) {
                    HStack(spacing: 3) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                        Text(city)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(PawPalTheme.tertiaryText)
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(10)
        .background(PawPalTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: PawPalTheme.shadow, radius: 10, y: 4)
    }

    private var speciesEmoji: String {
        switch pet.species?.lowercased() {
        case "dog": return "🐶"
        case "cat": return "🐱"
        case "rabbit", "bunny": return "🐰"
        case "bird": return "🦜"
        case "hamster": return "🐹"
        default: return "🐾"
        }
    }

    private var metaLine: String? {
        let pieces = [trimmed(pet.species), trimmed(pet.breed), trimmed(pet.age)]
            .compactMap { $0 }
        return pieces.isEmpty ? nil : pieces.joined(separator: " · ")
    }

    private func trimmed(_ val: String?) -> String? {
        guard let v = val?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        return v
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
