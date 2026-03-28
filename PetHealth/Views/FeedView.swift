import SwiftUI
import SwiftData

struct FeedView: View {
    @Query(sort: \StoredPost.createdAt, order: .reverse) private var posts: [StoredPost]

    var body: some View {
        List {
            Section {
                headerRow
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)

            if posts.isEmpty {
                Section {
                    VStack(alignment: .center, spacing: 12) {
                        Image(systemName: "pawprint.circle")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("No moments yet")
                            .font(.headline)
                        Text("Post a small update about your pet and it will appear here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
            } else {
                ForEach(posts) { post in
                    momentRow(post)
                        .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Moments")
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(Color.orange.opacity(0.18))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "pawprint.fill")
                        .foregroundStyle(.orange)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("Pet Moments")
                    .font(.headline)
                Text("A simple local timeline for your pets.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func momentRow(_ post: StoredPost) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Color.blue.opacity(0.14))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: "pawprint.fill")
                            .foregroundStyle(.blue)
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

            Text(post.caption)
                .font(.body)
                .foregroundStyle(.primary)

            let images = post.imageDataList
            if !images.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, data in
                        if let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 88)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }

            if !post.mood.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(post.mood)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
