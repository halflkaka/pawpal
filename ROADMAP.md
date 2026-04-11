# PawPal Roadmap

## Current State
- ✅ Auth (sign in / register)
- ✅ User profile + pet management
- 🔲 Posts (local SwiftData stub only)
- 🔲 Feed (stub)
- 🔲 Chat (stub)

---

## Phase 1 — Real Posts & Feed
Wire the social core to Supabase.

- `PostsService` — fetch posts and images from `posts` + `post_images` tables, paginated
- Photo picker + upload to Supabase Storage, store URLs in `post_images`
- Real `FeedView` — scrolling feed with pet avatar, caption, images, mood tag, like/comment counts
- `CreatePostView` — save posts remotely instead of locally
- Retire `StoredPost` SwiftData model

## Phase 2 — Engagement
- Likes and comments on posts
- Follow / unfollow other users
- Notification badges
- "Following" feed tab filtered to accounts you follow

## Phase 3 — Discovery
- Explore / search page — browse pets by species, find users by username, trending posts
- Hashtag or mood-tag filtering (`mood` field already exists on `posts` table)

## Phase 4 — Pet Profiles as First-Class Pages
- Tapping a pet chip opens a dedicated pet profile — photo, bio, stats, post grid
- Pet-specific follow (follow a pet, not just a user)
- Profile photo upload for user avatars and pet avatars

## Phase 5 — Messaging
- Direct messages between users
- `ChatListView` stub already in codebase — wire to Supabase Realtime or a messages table

## Phase 6 — Polish & Growth
- Push notifications (likes, comments, new followers)
- Onboarding flow for new users
- App Store assets, privacy policy, TestFlight beta
- Feed algorithm (recency + social graph weighting)
