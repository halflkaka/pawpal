import SwiftUI
import UIKit

/// Owner-only "看过这条 Story" sheet. Surfaced from the viewer chip on
/// `StoryViewerView` and populated by `StoryService.viewers(storyID:)`.
/// Non-owners never see this view — the chip that opens it is itself
/// gated on ownership, and RLS on `story_views` would return zero rows
/// to a non-owner call anyway.
///
/// Shape mirrors `FollowListView` at a smaller scale: a list of
/// pet-first rows (avatar + name + relative timestamp), tap to push
/// `PetProfileView`. A `ProgressView` covers the loading state, an
/// empty-state panel covers the "no views yet" case, and pull-to-
/// refresh reloads the list.
///
/// Presentation notes:
///   * Wrapped in a `NavigationStack` so tapping a row can push
///     `PetProfileView` without requiring the caller to host a stack.
///     The enclosing context is a sheet presented from
///     `StoryViewerView`, itself presented as a `fullScreenCover` —
///     pushing a nav stack inside the sheet keeps the story viewer's
///     immersive black canvas intact underneath.
///   * Uses `PawPalBackground` for the warm cream surface matching
///     `PetProfileView` and the rest of the app's non-viewer chrome.
struct StoryViewersSheet: View {
    let storyID: UUID

    /// Three-state load model. Mirrors the `.loading` / `.loaded` /
    /// `.empty` convention used across the app. Collapsing to a
    /// single enum keeps the view body branch-light and makes the
    /// loading → loaded transition atomic (no flicker between "no
    /// data" and "ProgressView").
    private enum LoadState: Equatable {
        case loading
        case loaded([RemoteStoryView])

        var viewers: [RemoteStoryView] {
            if case .loaded(let rows) = self { return rows }
            return []
        }
    }

    @State private var state: LoadState = .loading
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                PawPalBackground()
                content
            }
            .navigationTitle("看过这条 Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    }
                    .foregroundStyle(PawPalTheme.primaryText)
                }
            }
            .navigationDestination(for: RemotePet.self) { pet in
                PetProfileView(pet: pet)
            }
        }
        .task {
            await load()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
                .tint(PawPalTheme.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let rows) where rows.isEmpty:
            emptyState
        case .loaded(let rows):
            list(for: rows)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "eye.slash")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(PawPalTheme.tertiaryText)
            Text("还没有人看过这条 Story")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PawPalTheme.primaryText)
            Text("分享给好友，让他们第一时间看到")
                .font(.system(size: 13))
                .foregroundStyle(PawPalTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    private func list(for rows: [RemoteStoryView]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                subtitle(count: rows.count)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                ForEach(rows) { row in
                    viewerRow(for: row)
                    Rectangle()
                        .fill(PawPalTheme.hairline)
                        .frame(height: 0.5)
                        .padding(.leading, 72)   // inset under avatar
                }
            }
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await load()
        }
    }

    private func subtitle(count: Int) -> some View {
        Text("\(count) 位毛孩子看过")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(PawPalTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Rows

    @ViewBuilder
    private func viewerRow(for row: RemoteStoryView) -> some View {
        if let pet = row.pet {
            NavigationLink(value: pet) {
                rowContent(pet: pet, viewedAt: row.viewed_at)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            })
        } else {
            // Pet join unavailable (rare — RLS or a race with a
            // deleted pet) — render the row inert rather than
            // hiding it so the owner still sees a receipt exists.
            rowContent(pet: nil, viewedAt: row.viewed_at)
        }
    }

    private func rowContent(pet: RemotePet?, viewedAt: Date) -> some View {
        HStack(spacing: 12) {
            PawPalAvatar(
                emoji: speciesEmoji(for: pet?.species ?? ""),
                imageURL: pet?.avatar_url,
                size: 44,
                background: PawPalTheme.cardSoft,
                dogBreed: pet?.species
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(pet?.name ?? "未知毛孩子")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PawPalTheme.primaryText)
                    .lineLimit(1)
                Text(relativeTime(from: viewedAt))
                    .font(.system(size: 12))
                    .foregroundStyle(PawPalTheme.tertiaryText)
            }
            Spacer(minLength: 8)
            if pet != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PawPalTheme.tertiaryText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Data

    private func load() async {
        // Don't stomp the current `.loaded` state with `.loading` on
        // pull-to-refresh — the built-in refreshable indicator owns
        // the spinner UX, and flipping back to a full-screen
        // ProgressView would read as a layout flash. We only flip
        // to `.loading` on the first pass (state == .loading
        // already, so the guard is a no-op on refresh).
        let rows = (try? await StoryService.shared.viewers(storyID: storyID)) ?? []
        state = .loaded(rows)
    }

    // MARK: - Helpers

    /// Emoji fallback used by `PawPalAvatar` for cats / rabbits /
    /// etc. where `DogAvatar` doesn't apply. Same mapping as the
    /// viewer header and `FollowListView`.
    private func speciesEmoji(for species: String) -> String {
        switch species.lowercased() {
        case "dog":             return "🐶"
        case "cat":             return "🐱"
        case "rabbit", "bunny": return "🐰"
        case "bird":            return "🦜"
        case "hamster":         return "🐹"
        case "fish":            return "🐟"
        default:                return "🐾"
        }
    }

    /// Chinese relative timestamp — "刚刚 / 3 分钟前 / 1 小时前 /
    /// 昨天 14:30 / 2025-04-15". Stories cap at 24h so the
    /// "昨天" branch is only hit for receipts that landed after
    /// midnight but before the 24h expiry; the day-before fallback
    /// is defensive (a viewer sheet could be opened just before
    /// expiry).
    private func relativeTime(from date: Date) -> String {
        let s = max(0, Int(-date.timeIntervalSinceNow))
        if s < 60     { return "刚刚" }
        if s < 3600   { return "\(s / 60) 分钟前" }

        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return "\(s / 3600) 小时前"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hans_CN")
        if cal.isDateInYesterday(date) {
            f.dateFormat = "昨天 HH:mm"
            return f.string(from: date)
        }
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
