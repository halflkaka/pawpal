import SwiftUI
import SwiftData

struct FeedView: View {
    @Query(sort: \StoredPost.createdAt, order: .reverse) private var posts: [StoredPost]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if posts.isEmpty {
                    ContentUnavailableView(
                        "No Posts Yet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Create your first pet post to start the feed.")
                    )
                    .padding(.top, 60)
                } else {
                    ForEach(posts) { post in
                        postCard(post)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Feed")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pet Feed")
                .font(.title2.bold())
            Text("A local-first space for pet updates, memories, and little moments.")
                .foregroundStyle(.secondary)
        }
    }

    private func postCard(_ post: StoredPost) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "pawprint.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.petName.isEmpty ? "Pet Post" : post.petName)
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

            if !post.mood.isEmpty {
                Text(post.mood)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.14))
                    .clipShape(Capsule())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
