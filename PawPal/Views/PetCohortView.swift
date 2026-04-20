import SwiftUI
import UIKit

/// Full-screen, paginated list of pets in a single breed or city
/// cohort — the "see all of X" surface reached by tapping a breed
/// pill or city pill from anywhere in the app (currently the
/// `PetProfileView` pills and the Discover "查看全部" header links).
///
/// The Discover rails cap at 12 and mix criteria; this view is the
/// "all of them, ordered by recency" view. Kind is an enum so the same
/// pager handles both breed and city without duplicating state. No
/// search / filtering inside the cohort view by design — the cohort
/// filter IS the query.
///
/// Pagination: offset-based, `pageSize` rows per call. When a page
/// returns fewer than `pageSize`, `hasMore` flips to false and the
/// bottom-reached trigger stops firing.
@MainActor
struct PetCohortView: View {
    // MARK: - Kind

    /// Which cohort this view lists. `Hashable` so the enum can drive
    /// a `NavigationLink(value:)` push from any parent stack without
    /// per-case destinations.
    enum Kind: Hashable {
        case breed(String)   // e.g. "柴犬"
        case city(String)    // e.g. "上海"

        var titleZh: String {
            switch self {
            case .breed(let b): return "\(b) 的毛孩子"
            case .city(let c):  return "\(c) 的毛孩子"
            }
        }

        var emptyCopyZh: String {
            switch self {
            case .breed(let b): return "还没有 \(b) 在 PawPal 上 🐾"
            case .city(let c):  return "还没有 \(c) 的毛孩子在 PawPal 上 🐾"
            }
        }
    }

    let kind: Kind
    /// Optional — when set, the viewer's own pets are filtered out of
    /// the cohort list. Callers who want the viewer included (e.g. a
    /// signed-out visitor) simply pass nil.
    var excludingOwnerID: UUID?
    /// Plumbs through to the pushed `PetProfileView` so message /
    /// playdate affordances there keep working. Matches the pattern
    /// used by `DiscoverView.navigationDestination(for: RemotePet.self)`.
    var currentUserID: UUID?
    var currentUserDisplayName: String = "用户"
    var currentUsername: String?
    var authManager: AuthManager?

    // MARK: - Pagination state

    /// Rows per page. Matches the `PetsService.fetchPetsByBreed` /
    /// `fetchPetsByCity` default so the service signature doesn't drift.
    private let pageSize: Int = 24

    @State private var pets: [RemotePet] = []
    @State private var offset: Int = 0
    @State private var hasMore: Bool = true
    @State private var isInitialLoading: Bool = false
    @State private var isLoadingMore: Bool = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if isInitialLoading && pets.isEmpty {
                    loadingBlock
                } else if pets.isEmpty {
                    emptyBlock
                } else {
                    grid
                    if hasMore {
                        paginationFooter
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(PawPalBackground())
        .navigationTitle(kind.titleZh)
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: RemotePet.self) { pet in
            PetProfileView(
                pet: pet,
                currentUserID: currentUserID,
                currentUserDisplayName: currentUserDisplayName,
                currentUsername: currentUsername,
                authManager: authManager
            )
        }
        .refreshable {
            await reload()
        }
        .task {
            // `.task` re-runs if the kind changes (e.g. same view
            // instance reused), so guard on `pets.isEmpty` to avoid
            // re-fetching the same first page on every appear. Pull-
            // to-refresh remains the explicit reset path.
            if pets.isEmpty {
                await loadFirstPage()
            }
        }
    }

    // MARK: - Loading states

    private var loadingBlock: some View {
        VStack {
            Spacer(minLength: 120)
            ProgressView()
                .tint(PawPalTheme.accent)
            Spacer(minLength: 120)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyBlock: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 80)
            Text("🐾")
                .font(.system(size: 44))
            Text(kind.emptyCopyZh)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PawPalTheme.secondaryText)
                .multilineTextAlignment(.center)
            Spacer(minLength: 80)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: - Grid

    /// Two-column grid matching the visual density of existing rails —
    /// dense enough to browse an active cohort, loose enough that each
    /// cell reads as a real card (not a thumbnail strip). 12pt gutter
    /// mirrors the post grid on `PetProfileView`.
    private var grid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            ForEach(pets) { pet in
                NavigationLink(value: pet) {
                    PetCohortCell(pet: pet)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                )
                .onAppear {
                    // Trigger the next page when the ForEach hydrates
                    // a row near the tail. Comparing by id keeps the
                    // check O(1) vs. computing an index on every
                    // onAppear, and using the last existing pet means
                    // we kick off the fetch *before* the user hits a
                    // dead bottom.
                    if pet.id == pets.last?.id {
                        Task { await loadNextPage() }
                    }
                }
            }
        }
    }

    private var paginationFooter: some View {
        HStack {
            Spacer()
            if isLoadingMore {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(PawPalTheme.accent)
                    Text("加载中…")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PawPalTheme.tertiaryText)
                }
            }
            Spacer()
        }
        .frame(height: 44)
        .padding(.top, 12)
    }

    // MARK: - Load strategy

    /// Pull-to-refresh / first-view entry point. Resets the page
    /// counter so the service starts at offset 0 again — critical
    /// because a stale `offset` would otherwise skip the freshest
    /// rows after a new pet joins the cohort.
    private func reload() async {
        offset = 0
        hasMore = true
        pets = []
        await loadFirstPage()
    }

    private func loadFirstPage() async {
        isInitialLoading = true
        defer { isInitialLoading = false }
        let page = await fetchPage(offset: 0)
        pets = page
        offset = page.count
        hasMore = page.count == pageSize
    }

    private func loadNextPage() async {
        guard hasMore, !isLoadingMore, !isInitialLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let page = await fetchPage(offset: offset)
        // Defensive dedupe: if two `onAppear` triggers race on the
        // same tail row we don't want to double-append. A set lookup
        // across ~24 rows is cheap.
        let existing = Set(pets.map(\.id))
        let fresh = page.filter { !existing.contains($0.id) }
        pets.append(contentsOf: fresh)
        offset += page.count
        hasMore = page.count == pageSize
    }

    /// Dispatches to the right `PetsService` method based on `kind`.
    /// Keeping the switch inside the view (vs. a `fetch(for:)` helper
    /// on the service) means the service stays a thin PostgREST
    /// wrapper with one job per method.
    private func fetchPage(offset: Int) async -> [RemotePet] {
        switch kind {
        case .breed(let breed):
            return await PetsService.shared.fetchPetsByBreed(
                breed,
                excludingOwnerID: excludingOwnerID,
                limit: pageSize,
                offset: offset
            )
        case .city(let city):
            return await PetsService.shared.fetchPetsByCity(
                city,
                excludingOwnerID: excludingOwnerID,
                limit: pageSize,
                offset: offset
            )
        }
    }
}

// MARK: - PetCohortCell

/// Single card in the cohort grid. Avatar + name + breed/city
/// secondary line + an optional boop pill when the pet has ≥1 boop —
/// the same visual language as `PetRailCard` on Discover, retuned to
/// fit a full-width two-column layout.
private struct PetCohortCell: View {
    let pet: RemotePet

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                avatar
                VStack(alignment: .leading, spacing: 3) {
                    Text(pet.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(PawPalTheme.primaryText)
                        .lineLimit(1)
                    if let secondary {
                        Text(secondary)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PawPalTheme.tertiaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            if let count = pet.boop_count, count > 0 {
                boopPill(count: count)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(PawPalTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PawPalTheme.hairline, lineWidth: 0.5)
        )
        .shadow(color: PawPalTheme.softShadow, radius: 6, y: 2)
    }

    /// Prefer breed as the secondary line when present, else fall back
    /// to city — breed is the more specific signal for pet identity.
    /// Returns nil when both are empty so the row collapses cleanly.
    private var secondary: String? {
        if let b = trimmed(pet.breed) { return b }
        if let c = trimmed(pet.home_city) { return c }
        return nil
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(PawPalTheme.cardSoft)
                .frame(width: 48, height: 48)
            if let urlStr = pet.avatar_url, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                    } else {
                        Text(speciesEmoji)
                            .font(.system(size: 24))
                    }
                }
            } else {
                Text(speciesEmoji)
                    .font(.system(size: 24))
            }
        }
        .overlay(
            Circle().stroke(PawPalTheme.orangeGlow.opacity(0.6), lineWidth: 1.5)
        )
    }

    private func boopPill(count: Int) -> some View {
        HStack(spacing: 4) {
            Text("🔥")
                .font(.system(size: 10))
            Text("\(count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.accent)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(PawPalTheme.accent.opacity(0.12), in: Capsule())
    }

    private var speciesEmoji: String {
        switch pet.species?.lowercased() {
        case "dog":             return "🐶"
        case "cat":             return "🐱"
        case "rabbit", "bunny": return "🐰"
        case "bird":            return "🦜"
        case "fish":            return "🐟"
        case "hamster":         return "🐹"
        default:                return "🐾"
        }
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
