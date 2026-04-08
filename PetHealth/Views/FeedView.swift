import SwiftUI
import SwiftData

struct FeedView: View {
    @Query(sort: \StoredPost.createdAt, order: .reverse) private var posts: [StoredPost]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                topIntro

                if posts.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 18) {
                        ForEach(posts) { post in
                            momentCard(post)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Moments")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var topIntro: some View {
        HStack(alignment: .center, spacing: 14) {
            Circle()
                .fill(Color.orange.opacity(0.14))
                .frame(width: 54, height: 54)
                .overlay {
                    Image(systemName: "pawprint.fill")
                        .foregroundStyle(.orange)
                }

            Text("Moments")
                .font(.system(size: 30, weight: .bold))

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.16), Color.pink.opacity(0.08), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)

            Text("No moments yet")
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .padding(.horizontal, 24)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func momentCard(_ post: StoredPost) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(Color.orange.opacity(0.16))
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: "pawprint.fill")
                            .foregroundStyle(.orange)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(post.petName.isEmpty ? "Pet" : post.petName)
                        .font(.headline)
                    Text(post.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if !post.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(post.caption)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
            }

            let images = post.imageDataList
            if !images.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, data in
                        if let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 168)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }
            }

            if !post.mood.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(post.mood)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.04))
                    .clipShape(Capsule())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
