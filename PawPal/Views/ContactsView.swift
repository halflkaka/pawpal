import SwiftUI

struct ContactsView: View {
    @State private var selectedFilter = "全部"

    private let filters = ["全部", "狗狗", "猫咪", "兔兔", "鸟类"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                searchBar
                filterRow
                spotsGrid
                trendsSection
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
        VStack(alignment: .leading, spacing: 10) {
            Text("发现 🔭")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
            Text("发现宠物、地点和超有人气的小明星")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
            Text("搜索宠物、话题、地点…")
            Spacer()
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: PawPalTheme.shadow, radius: 10, y: 4)
    }

    private var filterRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.self) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter)
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

    private var spotsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            PawPalSectionTitle(title: "热门地点", emoji: "✨")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(exploreCards) { card in
                    VStack(alignment: .leading, spacing: 0) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(card.background)
                            .frame(height: 94)
                            .overlay {
                                Text(card.emoji)
                                    .font(.system(size: 44))
                            }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.name)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(PawPalTheme.primaryText)
                            Text(card.meta)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                    }
                    .pawPalCard(padding: 0)
                }
            }
        }
    }

    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            PawPalSectionTitle(title: "热门话题", emoji: "🔥")

            ForEach(Array(trending.enumerated()), id: \.element.id) { index, trend in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(PawPalTheme.orangeSoft)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(trend.tag)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(PawPalTheme.primaryText)
                        Text(trend.count)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(trend.emoji)
                        .font(.system(size: 22))
                }
                .pawPalCard()
            }
        }
    }
}

private struct ExploreCard: Identifiable {
    let id = UUID()
    let emoji: String
    let background: LinearGradient
    let name: String
    let meta: String
}

private struct TrendItem: Identifiable {
    let id = UUID()
    let tag: String
    let count: String
    let emoji: String
}

private let exploreCards: [ExploreCard] = [
    .init(emoji: "🐕", background: LinearGradient(colors: [Color(red: 1.0, green: 0.88, blue: 0.70), Color(red: 1.0, green: 0.80, blue: 0.50)], startPoint: .topLeading, endPoint: .bottomTrailing), name: "金色时刻", meta: "金毛 · 4.2K 帖子"),
    .init(emoji: "🐈", background: LinearGradient(colors: [Color(red: 0.72, green: 0.87, blue: 0.94), Color(red: 0.83, green: 0.72, blue: 0.94)], startPoint: .topLeading, endPoint: .bottomTrailing), name: "猫猫午睡", meta: "猫咪 · 8.1K 帖子"),
    .init(emoji: "🐇", background: LinearGradient(colors: [Color(red: 0.83, green: 0.94, blue: 0.72), Color(red: 0.72, green: 0.94, blue: 0.83)], startPoint: .topLeading, endPoint: .bottomTrailing), name: "兔兔蹦跳", meta: "兔兔 · 2.3K 帖子"),
    .init(emoji: "🦜", background: LinearGradient(colors: [Color(red: 0.94, green: 0.83, blue: 0.72), Color(red: 0.94, green: 0.72, blue: 0.72)], startPoint: .topLeading, endPoint: .bottomTrailing), name: "鹦鹉开麦", meta: "鸟类 · 1.8K 帖子")
]

private let trending: [TrendItem] = [
    .init(tag: "#疯跑时间", count: "12.4K 帖子", emoji: "🌀"),
    .init(tag: "#湿鼻子星期三", count: "8.1K 帖子", emoji: "💧"),
    .init(tag: "#午睡小分队", count: "6.7K 帖子", emoji: "😴"),
    .init(tag: "#碰鼻子", count: "4.2K 帖子", emoji: "👃")
]
