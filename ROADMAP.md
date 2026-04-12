# PawPal Roadmap

## Current State

Phases 1 and 2 are complete. Phase 3 is partially done. Phases 4–6 are upcoming.

---

## Phase 1 — Real Posts & Feed ✅ Complete

- Real feed loading from Supabase with multi-level query fallback for resilience
- Post creation with image upload to Supabase Storage
- `CreatePostView` fully wired — pet selection, caption, mood, images
- SwiftData local models retired

## Phase 2 — Engagement ✅ Complete

- Likes and comments on posts — real Supabase queries with optimistic updates
- Follow / unfollow — `FollowService` with real follow/unfollow/toggle and follower counts
- Feed filtered to followed users + self
- ⚠️ Notification badges not yet implemented

## Phase 3 — Discovery ⚠️ Partial

- `ContactsView` loads real posts and supports filtering by mood and species
- Search works client-side across pet name, species, breed, city, caption, mood
- Trending topics derived dynamically from real post data
- 🔲 True pet-first explore (browse by breed, find pets near you) not yet built — current discovery is post-based filtering, not pet-based browsing

## Phase 4 — Pet Profiles as First-Class Pages 🔲 Not started

- Pet management (add, edit, delete) is fully real in `ProfileView`
- 🔲 Dedicated pet profile page — tap a pet to see its photo, bio, stats, post grid
- 🔲 Pet-specific follow (follow a pet, not just a user)
- 🔲 Profile photo upload for user avatars and pet avatars

## Phase 5 — Messaging 🔲 Stub only

- `ChatListView` exists with hardcoded placeholder chat previews
- No backend, no service, no real data
- Requires Supabase Realtime or a messages table

## Phase 6 — Polish & Growth 🔲 Not started

- Push notifications (likes, comments, new followers)
- Onboarding flow for new users
- Feed algorithm (recency + social graph weighting)
- App Store assets, privacy policy, TestFlight beta
