import SwiftUI

struct PetProfileView: View {
    let pet: RemotePet
    @StateObject private var postsService = PostsService()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                petHeader
                Divider()
                postsGrid
            }
        }
        .scrollIndicators(.hidden)
        .background(PawPalBackground())
        .navigationTitle(pet.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await postsService.loadPetPosts(for: pet.id) }
        .task { await postsService.loadPetPosts(for: pet.id) }
    }

    // MARK: - Header

    private var petHeader: some View {
        VStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [PawPalTheme.orange.opacity(0.28), PawPalTheme.cardSoft],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 96, height: 96)
                    .shadow(color: PawPalTheme.orange.opacity(0.22), radius: 18, y: 8)
                Text(speciesEmoji(for: pet.species ?? ""))
                    .font(.system(size: 48))
            }
            .overlay(Circle().stroke(PawPalTheme.orange.opacity(0.35), lineWidth: 3))

            // Name
            Text(pet.name)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)

            // Tag pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let species = pet.species, !species.isEmpty {
                        PawPalPill(text: speciesDisplayName(species), systemImage: "pawprint.fill", tint: PawPalTheme.orange)
                    }
                    if let breed = pet.breed, !breed.isEmpty {
                        PawPalPill(text: breed, systemImage: nil, tint: PawPalTheme.secondaryText)
                    }
                    if let age = pet.age, !age.isEmpty {
                        PawPalPill(text: age, systemImage: "calendar", tint: PawPalTheme.tertiaryText)
                    }
                    if let sex = pet.sex, !sex.isEmpty {
                        PawPalPill(text: sex, systemImage: nil, tint: PawPalTheme.tertiaryText)
                    }
                    if let weight = pet.weight, !weight.isEmpty {
                        PawPalPill(text: weight, systemImage: "scalemass", tint: PawPalTheme.tertiaryText)
                    }
                }
                .padding(.horizontal, 20)
            }

            // City
            if let city = pet.home_city, !city.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 11))
                    Text(city)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(PawPalTheme.tertiaryText)
            }

            // Bio
            if let bio = pet.bio, !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(bio)
                    .font(.system(size: 14))
                    .foregroundStyle(PawPalTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 24)
            }

            // Stats
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("\(postsService.petPosts.count)")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(PawPalTheme.primaryText)
                    Text("帖子")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 28)
    }

    // MARK: - Posts grid

    private var postsGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PawPalTheme.orange)
                Text("动态")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.primaryText)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            if postsService.isLoadingFeed && postsService.petPosts.isEmpty {
                ProgressView().padding(.top, 48)
            } else if postsService.petPosts.isEmpty {
                emptyPostsState
            } else {
                realPostsGrid
            }
        }
    }

    private var emptyPostsState: some View {
        VStack(spacing: 12) {
            Text("🐾")
                .font(.system(size: 44))
                .padding(.top, 40)
            Text("还没有动态")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
            Text("\(pet.name) 还没有发布任何动态")
                .font(.system(size: 14))
                .foregroundStyle(PawPalTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 48)
    }

    private var realPostsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            ForEach(postsService.petPosts) { post in
                petPostTile(post)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func petPostTile(_ post: RemotePost) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let imageURL = post.imageURLs.first {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                            .frame(height: 150).frame(maxWidth: .infinity).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    case .failure:
                        tilePlaceholder(height: 150, icon: "photo")
                    default:
                        tilePlaceholder(height: 150, icon: nil)
                    }
                }
            } else {
                tilePlaceholder(height: 150, icon: "text.alignleft")
            }

            Text(post.caption)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PawPalTheme.primaryText)
                .lineLimit(2)
                .padding(.horizontal, 6)

            HStack(spacing: 8) {
                Label("\(post.likeCount)", systemImage: "heart")
                Label("\(post.commentCount)", systemImage: "message")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(PawPalTheme.tertiaryText)
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        }
        .background(PawPalTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: PawPalTheme.softShadow, radius: 8, y: 3)
    }

    private func tilePlaceholder(height: CGFloat, icon: String?) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(PawPalTheme.cardSoft)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(PawPalTheme.tertiaryText)
                } else {
                    ProgressView()
                }
            }
    }

    // MARK: - Helpers

    private func speciesEmoji(for species: String) -> String {
        switch species.lowercased() {
        case "dog": return "🐶"
        case "cat": return "🐱"
        case "rabbit", "bunny": return "🐰"
        case "bird": return "🦜"
        case "hamster": return "🐹"
        case "fish": return "🐟"
        default: return "🐾"
        }
    }

    private func speciesDisplayName(_ species: String) -> String {
        switch species.lowercased() {
        case "dog": return "狗狗"
        case "cat": return "猫咪"
        case "rabbit", "bunny": return "兔兔"
        case "bird": return "鸟类"
        case "hamster": return "仓鼠"
        case "fish": return "鱼类"
        default: return species
        }
    }
}
