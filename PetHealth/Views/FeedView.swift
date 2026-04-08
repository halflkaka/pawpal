import SwiftUI
import SwiftData

struct FeedView: View {
    @Query(sort: \StoredPost.createdAt, order: .reverse) private var posts: [StoredPost]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                if posts.isEmpty {
                    emptyState
                        .padding(.top, 80)
                        .padding(.horizontal, 24)
                } else {
                    ForEach(posts) { post in
                        momentRow(post)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                        Divider()
                            .padding(.leading, 72)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("Moments")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(.secondarySystemBackground))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.gray)
                }

            Text("Moments")
                .font(.system(size: 22, weight: .semibold))

            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No moments")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func momentRow(_ post: StoredPost) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                avatar

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(post.petName.isEmpty ? "Pet" : post.petName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(red: 0.22, green: 0.34, blue: 0.52))

                        Spacer()
                    }

                    if !post.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(post.caption)
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                            .lineSpacing(3)
                    }

                    let images = post.imageDataList
                    if !images.isEmpty {
                        imageGrid(images)
                    }

                    HStack(spacing: 8) {
                        if !post.mood.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(post.mood)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(post.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var avatar: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(.secondarySystemBackground))
            .frame(width: 48, height: 48)
            .overlay {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.gray)
            }
    }

    private func imageGrid(_ images: [Data]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: min(images.count == 1 ? 1 : 3, 3))

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(Array(images.enumerated()), id: \.offset) { _, data in
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: imageWidth(for: images.count), height: imageWidth(for: images.count))
                        .clipped()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func imageWidth(for count: Int) -> CGFloat {
        if count == 1 { return 180 }
        return 92
    }
}
