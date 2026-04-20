import SwiftUI
import UIKit

/// Pet-first discovery page. One hero card plus five horizontal rails:
/// 0) Pet of the Day (single rotating hero, top of the page)
/// 1) Similar pets (species + breed/city match against the user's featured pet)
/// 2) Popular pets (ordered by boop_count)
/// 3) Recent activity (pets that posted in the last 48h the viewer doesn't follow)
/// 4) Nearby pets (shares the featured pet's home_city)
/// 5) Open to playdates (pets flagged `open_to_playdates = true`, viewer's
///    city bubbled to the top)
///
/// Replaces the old `ContactsView` which was a mood-trending + search layer
/// over feed posts. See docs/product.md ("pet as protagonist") for why we
/// swapped that out.
struct DiscoverView: View {
    @Bindable var authManager: AuthManager
    @AppStorage("activePetID") private var activePetID = ""

    /// Invoked when the user taps the "先添加你的毛孩子" empty-state card.
    /// Wired by `MainTabView` to switch to the Me tab so the user lands on
    /// the existing add-pet flow there.
    var onAddPetRequested: (() -> Void)?

    @ObservedObject private var petsService = PetsService.shared

    /// Per-view `FollowService` mirrors the pattern in `FeedView` /
    /// `ProfileView` — the service isn't a `.shared` singleton, each
    /// consumer owns its own loader. We use `followingIDs` to dedupe
    /// the Recent Activity rail against accounts the viewer already
    /// follows.
    @StateObject private var followService = FollowService()

    @State private var petOfTheDay: RemotePet?
    @State private var similarPets: [RemotePet] = []
    @State private var popularPets: [RemotePet] = []
    @State private var recentActivityPets: [RemotePet] = []
    @State private var nearbyPets: [RemotePet] = []
    @State private var openToPlaydatesPets: [RemotePet] = []

    @State private var isLoadingPetOfTheDay = false
    @State private var isLoadingSimilar = false
    @State private var isLoadingPopular = false
    @State private var isLoadingRecentActivity = false
    @State private var isLoadingNearby = false
    @State private var isLoadingOpenToPlaydates = false

    @State private var searchText = ""

    /// The user's "featured" pet. Drives the Similar + Nearby rails.
    /// Falls back to the first pet in the list if `activePetID` is unset
    /// or stale.
    private var featuredPet: RemotePet? {
        if let id = UUID(uuidString: activePetID),
           let match = petsService.pets.first(where: { $0.id == id }) {
            return match
        }
        return petsService.pets.first
    }

    private var currentUserID: UUID? {
        authManager.currentUser?.id
    }

    private var nearbyCity: String? {
        let city = featuredPet?.home_city?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (city?.isEmpty ?? true) ? nil : city
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                searchBar

                petOfTheDaySection

                if petsService.pets.isEmpty {
                    noPetsCard
                }

                if featuredPet != nil {
                    similarRail
                }

                popularRail

                recentActivityRail

                if nearbyCity != nil {
                    nearbyRail
                }

                openToPlaydatesRail

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(PawPalBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: RemotePet.self) { pet in
            PetProfileView(
                pet: pet,
                currentUserID: currentUserID,
                currentUserDisplayName: authManager.currentUser?.displayName ?? "",
                currentUsername: authManager.currentProfile?.username,
                authManager: authManager
            )
        }
        // Cohort surface — pushed from the "查看全部" header link on
        // the similar / nearby rails. Single destination handles both
        // breed and city cases via the enum.
        .navigationDestination(for: PetCohortView.Kind.self) { kind in
            PetCohortView(
                kind: kind,
                excludingOwnerID: currentUserID,
                currentUserID: currentUserID,
                currentUserDisplayName: authManager.currentUser?.displayName ?? "",
                currentUsername: authManager.currentProfile?.username,
                authManager: authManager
            )
        }
        .task {
            await loadAllRails()
        }
        .refreshable {
            await loadAllRails()
        }
        .onChange(of: activePetID) { _, _ in
            Task { await loadSimilarAndNearby() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("发现")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
            Text("看看还有哪些毛孩子在等你")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PawPalTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PawPalTheme.tertiaryText)
            TextField("搜索毛孩子的名字…", text: $searchText)
                .font(.system(size: 14, weight: .semibold))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .tint(PawPalTheme.orange)

            if !searchText.isEmpty {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(PawPalTheme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(PawPalTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PawPalTheme.hairline, lineWidth: 0.5)
        )
        .shadow(color: PawPalTheme.softShadow, radius: 8, y: 2)
    }

    // MARK: - No-pets card

    private var noPetsCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onAddPetRequested?()
        } label: {
            HStack(spacing: 14) {
                Text("🐾")
                    .font(.system(size: 32))
                    .frame(width: 54, height: 54)
                    .background(PawPalTheme.orange.opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("先添加你的毛孩子，我们帮你找朋友")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(PawPalTheme.primaryText)
                        .multilineTextAlignment(.leading)
                    Text("去主页添加 TA")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PawPalTheme.orange)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PawPalTheme.orange)
            }
            .padding(16)
            .background(PawPalTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(PawPalTheme.orangeGlow, lineWidth: 1)
            )
            .shadow(color: PawPalTheme.softShadow, radius: 10, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pet of the Day

    /// Hero section rendered above the rails. We hide it entirely when
    /// the fetch returns nil *and* we're not still loading, so users on
    /// an empty DB don't see a dangling skeleton. When the active
    /// search text filters the hero out, we also hide — the card only
    /// appears when it actually matches.
    @ViewBuilder
    private var petOfTheDaySection: some View {
        if isLoadingPetOfTheDay {
            PetOfTheDayCard.skeleton
        } else if let pet = petOfTheDay, !filtered([pet]).isEmpty {
            PetOfTheDayCard(pet: pet)
        }
    }

    // MARK: - Rails

    private var similarRail: some View {
        Group {
            if isLoadingSimilar {
                railSection(
                    title: similarTitle,
                    emoji: "🫶",
                    badge: nil,
                    seeAll: similarSeeAllKind
                ) {
                    railProgressRow
                }
            } else if !filtered(similarPets).isEmpty {
                railSection(
                    title: similarTitle,
                    emoji: "🫶",
                    badge: nil,
                    seeAll: similarSeeAllKind
                ) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(filtered(similarPets)) { pet in
                                PetRailCard(pet: pet, variant: .similar)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    /// The "similar" rail blends breed + city; for the header link we
    /// prefer the breed cohort (more specific identity signal) and fall
    /// through to nothing when the featured pet has no breed. Per spec
    /// we'd rather show no link than route to the wrong cohort.
    private var similarSeeAllKind: PetCohortView.Kind? {
        guard let breed = featuredPet?.breed?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !breed.isEmpty
        else { return nil }
        return .breed(breed)
    }

    private var popularRail: some View {
        Group {
            if isLoadingPopular {
                railSection(
                    title: "人气毛孩子",
                    emoji: "🔥",
                    badge: nil
                ) {
                    railProgressRow
                }
            } else if !filtered(popularPets).isEmpty {
                railSection(
                    title: "人气毛孩子",
                    emoji: "🔥",
                    badge: nil
                ) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(filtered(popularPets)) { pet in
                                PetRailCard(pet: pet, variant: .popular)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var recentActivityRail: some View {
        Group {
            if isLoadingRecentActivity {
                railSection(
                    title: "最近在发的毛孩子",
                    emoji: "✨",
                    badge: nil
                ) {
                    railProgressRow
                }
            } else if !filtered(recentActivityPets).isEmpty {
                railSection(
                    title: "最近在发的毛孩子",
                    emoji: "✨",
                    badge: nil
                ) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(filtered(recentActivityPets)) { pet in
                                PetRailCard(pet: pet, variant: .recentlyActive)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var nearbyRail: some View {
        Group {
            if isLoadingNearby {
                railSection(
                    title: nearbyTitle,
                    emoji: "📍",
                    badge: nil,
                    seeAll: nearbySeeAllKind
                ) {
                    railProgressRow
                }
            } else if !filtered(nearbyPets).isEmpty {
                railSection(
                    title: nearbyTitle,
                    emoji: "📍",
                    badge: nil,
                    seeAll: nearbySeeAllKind
                ) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(filtered(nearbyPets)) { pet in
                                PetRailCard(pet: pet, variant: .nearby)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    /// The nearby rail is keyed on `nearbyCity`; when the featured pet
    /// has no `home_city` the rail itself is hidden upstream, so we
    /// never render a header link without a valid cohort.
    private var nearbySeeAllKind: PetCohortView.Kind? {
        guard let city = nearbyCity else { return nil }
        return .city(city)
    }

    /// "今天有空的毛孩子" — pets that have flipped `open_to_playdates`
    /// on. Hidden entirely when the result set is empty (no
    /// placeholder) so a viewer in a cold-start region doesn't see a
    /// dead rail.
    private var openToPlaydatesRail: some View {
        Group {
            if isLoadingOpenToPlaydates {
                railSection(
                    title: "今天有空的毛孩子",
                    emoji: "🐾",
                    badge: nil
                ) {
                    railProgressRow
                }
            } else if !filtered(openToPlaydatesPets).isEmpty {
                railSection(
                    title: "今天有空的毛孩子",
                    emoji: "🐾",
                    badge: nil
                ) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(filtered(openToPlaydatesPets)) { pet in
                                PlaydateAvailableRailCard(pet: pet)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var similarTitle: String {
        let name = featuredPet?.name ?? "你"
        return "与 \(name) 相似的毛孩子"
    }

    private var nearbyTitle: String {
        let city = nearbyCity ?? ""
        return "\(city) 的毛孩子"
    }

    private var railProgressRow: some View {
        HStack {
            Spacer()
            ProgressView()
                .padding(.vertical, 40)
            Spacer()
        }
    }

    // MARK: - Rail section container

    @ViewBuilder
    private func railSection<Content: View>(
        title: String,
        emoji: String,
        badge: String?,
        seeAll: PetCohortView.Kind? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 18))
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.primaryText)
                    .lineLimit(1)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(PawPalTheme.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(PawPalTheme.orange.opacity(0.12), in: Capsule())
                }
                // "查看全部" header link routes to the dedicated cohort
                // surface. Rendered only when the caller hands in a
                // Kind — other rails leave it off.
                if let seeAll {
                    NavigationLink(value: seeAll) {
                        HStack(spacing: 3) {
                            Text("查看全部")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(PawPalTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    })
                }
            }
            content()
        }
    }

    // MARK: - Search filter

    private func filtered(_ pets: [RemotePet]) -> [RemotePet] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return pets }
        return pets.filter {
            let fields = [$0.name, $0.species, $0.breed, $0.home_city]
                .compactMap { $0?.lowercased() }
            return fields.contains { $0.contains(q) }
        }
    }

    // MARK: - Load strategy

    private func loadAllRails() async {
        // Refresh follows first so the Recent Activity rail can dedupe
        // against the viewer's existing follow graph. We still kick off
        // the other rails in parallel with it — only `loadRecentActivity`
        // waits for the follow set.
        async let followsRefresh: () = refreshFollowing()
        async let hero: () = loadPetOfTheDay()
        async let s: () = loadSimilar()
        async let p: () = loadPopular()
        async let n: () = loadNearby()
        async let o: () = loadOpenToPlaydates()

        _ = await followsRefresh
        async let r: () = loadRecentActivity()
        _ = await (hero, s, p, n, r, o)
    }

    private func loadSimilarAndNearby() async {
        async let s: () = loadSimilar()
        async let n: () = loadNearby()
        _ = await (s, n)
    }

    private func refreshFollowing() async {
        guard let uid = currentUserID else { return }
        await followService.loadFollowing(for: uid)
    }

    private func loadPetOfTheDay() async {
        isLoadingPetOfTheDay = true
        let result = await PetsService.shared.fetchPetOfTheDay(
            excludingOwnerID: currentUserID
        )
        await MainActor.run {
            self.petOfTheDay = result
            self.isLoadingPetOfTheDay = false
        }
    }

    private func loadRecentActivity() async {
        isLoadingRecentActivity = true
        // `followingIDs` may be empty if the viewer is signed out or
        // hasn't followed anyone — pass it through regardless; the
        // service treats an empty set the same as "no follow filter".
        let follows: Set<UUID>? = currentUserID == nil ? nil : followService.followingIDs
        let result = await PetsService.shared.fetchRecentActivityPets(
            followingIDs: follows,
            excludingOwnerID: currentUserID,
            limit: 12
        )
        await MainActor.run {
            self.recentActivityPets = result
            self.isLoadingRecentActivity = false
        }
    }

    private func loadSimilar() async {
        guard let pet = featuredPet else {
            similarPets = []
            return
        }
        isLoadingSimilar = true
        let result = await PetsService.shared.fetchSimilarPets(to: pet, limit: 12)
        await MainActor.run {
            self.similarPets = result
            self.isLoadingSimilar = false
        }
    }

    private func loadPopular() async {
        isLoadingPopular = true
        let result = await PetsService.shared.fetchPopularPets(
            excludingOwnerID: currentUserID,
            limit: 12
        )
        await MainActor.run {
            self.popularPets = result
            self.isLoadingPopular = false
        }
    }

    private func loadNearby() async {
        guard let city = nearbyCity else {
            nearbyPets = []
            return
        }
        isLoadingNearby = true
        let result = await PetsService.shared.fetchNearbyPets(
            city: city,
            excludingOwnerID: currentUserID,
            limit: 12
        )
        await MainActor.run {
            self.nearbyPets = result
            self.isLoadingNearby = false
        }
    }

    /// Fetches pets with `open_to_playdates = true`, excluding the
    /// viewer's own. Requires `currentUserID` — a signed-out viewer
    /// sees no rail (the service method needs the uuid to build the
    /// exclusion filter).
    private func loadOpenToPlaydates() async {
        guard let uid = currentUserID else {
            openToPlaydatesPets = []
            return
        }
        isLoadingOpenToPlaydates = true
        let result = (try? await PetsService.shared.fetchOpenToPlaydates(
            excludingUserId: uid,
            viewerCity: nearbyCity,
            limit: 20
        )) ?? []
        await MainActor.run {
            self.openToPlaydatesPets = result
            self.isLoadingOpenToPlaydates = false
        }
    }
}

// MARK: - Rail card

private struct PetRailCard: View {
    let pet: RemotePet
    let variant: Variant

    enum Variant {
        case similar
        case popular
        case nearby
        /// Rail member of "最近在发的毛孩子" — shows a small 📸 badge on
        /// the avatar to read as "fresh posts" at a glance.
        case recentlyActive
    }

    var body: some View {
        NavigationLink(value: pet) {
            VStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    avatar
                    if (variant == .popular || variant == .recentlyActive),
                       let badge {
                        Text(badge)
                            .font(.system(size: 12))
                            .padding(5)
                            .background(.white, in: Circle())
                            .overlay(Circle().stroke(PawPalTheme.orangeGlow, lineWidth: 0.5))
                            .shadow(color: PawPalTheme.softShadow, radius: 3, y: 1)
                            .offset(x: 4, y: -2)
                    }
                }

                VStack(spacing: 4) {
                    Text(pet.name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(PawPalTheme.primaryText)
                        .lineLimit(1)

                    speciesChip

                    if variant == .nearby, let city = trimmed(pet.home_city) {
                        HStack(spacing: 3) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 9))
                            Text(city)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                        }
                        .foregroundStyle(PawPalTheme.tertiaryText)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(12)
            .frame(width: 110, height: 150)
            .background(PawPalTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(PawPalTheme.hairline, lineWidth: 0.5)
            )
            .shadow(color: PawPalTheme.softShadow, radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture().onEnded {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        )
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(PawPalTheme.cardSoft)
                .frame(width: 72, height: 72)

            if let urlStr = pet.avatar_url, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                    } else {
                        Text(speciesEmoji)
                            .font(.system(size: 36))
                    }
                }
            } else {
                Text(speciesEmoji)
                    .font(.system(size: 36))
            }
        }
        .overlay(
            Circle().stroke(PawPalTheme.orangeGlow.opacity(0.6), lineWidth: 1.5)
        )
    }

    private var speciesChip: some View {
        HStack(spacing: 3) {
            Text(speciesEmoji)
                .font(.system(size: 10))
            if let s = trimmed(pet.species) {
                Text(speciesDisplayName(s))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(PawPalTheme.secondaryText)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(PawPalTheme.cardSoft, in: Capsule())
    }

    private var badge: String? {
        switch variant {
        case .popular: return "🔥"
        case .recentlyActive: return "📸"
        case .similar, .nearby: return nil
        }
    }

    private var speciesEmoji: String {
        switch pet.species?.lowercased() {
        case "dog":            return "🐶"
        case "cat":            return "🐱"
        case "rabbit", "bunny": return "🐰"
        case "bird":           return "🦜"
        case "fish":           return "🐟"
        case "hamster":        return "🐹"
        default:               return "🐾"
        }
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func speciesDisplayName(_ english: String) -> String {
        switch english.lowercased() {
        case "dog": return "狗狗"
        case "cat": return "猫咪"
        case "rabbit", "bunny": return "兔兔"
        case "bird": return "鸟类"
        case "fish": return "鱼类"
        case "hamster": return "仓鼠"
        default: return english
        }
    }
}

// MARK: - Open-to-playdates rail card

/// Card for the "今天有空的毛孩子" rail. Distinct from `PetRailCard`
/// because the playdates rail emphasises the opt-in chip and surfaces
/// breed + city under the name (vs the species chip / recent-activity
/// badge used on the other rails). Card frame matches the rest of the
/// Discover rails so rows still line up visually.
private struct PlaydateAvailableRailCard: View {
    let pet: RemotePet

    var body: some View {
        NavigationLink(value: pet) {
            VStack(spacing: 10) {
                avatarWithChip

                VStack(spacing: 3) {
                    Text(pet.name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(PawPalTheme.primaryText)
                        .lineLimit(1)

                    if let metaLine {
                        Text(metaLine)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(PawPalTheme.primaryText.opacity(0.6))
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(12)
            .frame(width: 110, height: 150)
            .background(PawPalTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(PawPalTheme.hairline, lineWidth: 0.5)
            )
            .shadow(color: PawPalTheme.softShadow, radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture().onEnded {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        )
    }

    /// 80pt avatar with the "可约玩" chip pinned to the bottom-right.
    /// The chip uses the warm amber/yellow family from the design
    /// system so it reads as "sunny / available" without competing
    /// with the orange brand accent used for primary CTAs.
    private var avatarWithChip: some View {
        ZStack(alignment: .bottomTrailing) {
            avatar
            availableChip
                .offset(x: 4, y: 2)
        }
        .frame(width: 80, height: 80)
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(PawPalTheme.cardSoft)
                .frame(width: 80, height: 80)

            if let urlStr = pet.avatar_url, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                    } else {
                        Text(speciesEmoji)
                            .font(.system(size: 38))
                    }
                }
            } else {
                Text(speciesEmoji)
                    .font(.system(size: 38))
            }
        }
        .overlay(
            Circle().stroke(PawPalTheme.orangeGlow.opacity(0.6), lineWidth: 1.5)
        )
    }

    private var availableChip: some View {
        Text("可约玩")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(PawPalTheme.primaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PawPalTheme.amber)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white, lineWidth: 1)
            )
            .shadow(color: PawPalTheme.softShadow, radius: 2, y: 1)
    }

    /// Breed + city joined by a middle-dot when both are present; one
    /// of them alone when only one is. Returns nil for a completely
    /// empty pair so the view can omit the line entirely and keep the
    /// card tidy.
    private var metaLine: String? {
        let parts = [trimmed(pet.breed), trimmed(pet.home_city)]
            .compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private var speciesEmoji: String {
        switch pet.species?.lowercased() {
        case "dog":            return "🐶"
        case "cat":            return "🐱"
        case "rabbit", "bunny": return "🐰"
        case "bird":           return "🦜"
        case "fish":           return "🐟"
        case "hamster":        return "🐹"
        default:               return "🐾"
        }
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: - Pet of the Day hero

/// Big orange-tinted card at the top of Discover showcasing a rotating
/// "今日明星毛孩子". Roughly 2x the height of `PetRailCard` so it reads
/// as a hero rather than another rail tile. Tapping pushes the same
/// `PetProfileView` path every other card on this page uses.
private struct PetOfTheDayCard: View {
    let pet: RemotePet

    /// Fixed height keeps the skeleton and the real card visually
    /// aligned — no layout jitter when the fetch resolves.
    private static let cardHeight: CGFloat = 168

    var body: some View {
        NavigationLink(value: pet) {
            HStack(spacing: 14) {
                avatar

                VStack(alignment: .leading, spacing: 8) {
                    eyebrow
                    Text(pet.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(PawPalTheme.primaryText)
                        .lineLimit(1)
                    chipRow
                    boopBadge
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PawPalTheme.orange)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .frame(height: Self.cardHeight)
            .background(PawPalTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(PawPalTheme.orangeGlow, lineWidth: 1)
            )
            // Subtle orange tint so the hero reads as elevated without
            // overpowering the rails below it.
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(PawPalTheme.orange.opacity(0.06))
                    .allowsHitTesting(false)
            )
            .shadow(color: PawPalTheme.softShadow, radius: 12, y: 3)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture().onEnded {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        )
    }

    private var eyebrow: some View {
        HStack(spacing: 4) {
            Text("✨")
                .font(.system(size: 11))
            Text("今日明星毛孩子")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(1.2)
                .foregroundStyle(PawPalTheme.orange)
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(PawPalTheme.cardSoft)
                .frame(width: 96, height: 96)

            if let urlStr = pet.avatar_url, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                    } else {
                        Text(speciesEmoji)
                            .font(.system(size: 44))
                    }
                }
            } else {
                Text(speciesEmoji)
                    .font(.system(size: 44))
            }
        }
        .overlay(
            Circle().stroke(PawPalTheme.orangeGlow, lineWidth: 2)
        )
    }

    /// One-line chip row reusing the "pill" feel of the existing
    /// species / breed / city chips on rail cards. Picks up to three
    /// populated fields so a dense bio doesn't overflow on compact
    /// devices.
    private var chipRow: some View {
        HStack(spacing: 6) {
            ForEach(chips, id: \.self) { chip in
                Text(chip)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(PawPalTheme.secondaryText)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(PawPalTheme.cardSoft, in: Capsule())
            }
        }
    }

    private var chips: [String] {
        var out: [String] = []
        if let s = trimmed(pet.species) {
            out.append("\(speciesEmoji) \(speciesDisplayName(s))")
        }
        if let b = trimmed(pet.breed) {
            out.append(b)
        }
        if let c = trimmed(pet.home_city) {
            out.append("📍 \(c)")
        }
        return Array(out.prefix(3))
    }

    private var boopBadge: some View {
        HStack(spacing: 4) {
            Text("🔥")
                .font(.system(size: 11))
            Text("\(pet.boop_count ?? 0) 次 boop")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.orange)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(PawPalTheme.orange.opacity(0.12), in: Capsule())
    }

    private var speciesEmoji: String {
        switch pet.species?.lowercased() {
        case "dog":            return "🐶"
        case "cat":            return "🐱"
        case "rabbit", "bunny": return "🐰"
        case "bird":           return "🦜"
        case "fish":           return "🐟"
        case "hamster":        return "🐹"
        default:               return "🐾"
        }
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func speciesDisplayName(_ english: String) -> String {
        switch english.lowercased() {
        case "dog": return "狗狗"
        case "cat": return "猫咪"
        case "rabbit", "bunny": return "兔兔"
        case "bird": return "鸟类"
        case "fish": return "鱼类"
        case "hamster": return "仓鼠"
        default: return english
        }
    }

    /// Placeholder rendered while the hero fetch is in flight. Matches
    /// the final card's height + corner radius so the layout doesn't
    /// shift when real content arrives.
    static var skeleton: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(PawPalTheme.cardSoft)
            .frame(height: cardHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(PawPalTheme.hairline, lineWidth: 0.5)
            )
            .shadow(color: PawPalTheme.softShadow, radius: 8, y: 2)
    }
}
