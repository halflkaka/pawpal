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
- ✅ Post detail view — `PostDetailView` with inline comments, optimistic like button, pet avatar link, and pinned input bar (PR #11)
- ⚠️ Notification badges not yet implemented

## Phase 3 — Discovery ✅ Complete

- `ContactsView` loads real posts and supports filtering by mood and species
- Search works client-side across pet name, species, breed, city, caption, mood
- Trending topics derived dynamically from real post data
- Pet-first explore tab in `ContactsView` — browse all pets by species, tap to open pet profile (PR #7)

## Phase 4 — Pet Profiles as First-Class Pages ⚠️ Partial

- Pet management (add, edit, delete) is fully real in `ProfileView`
- ✅ Dedicated pet profile page (`PetProfileView`) — navigable from profile, shows bio, tag pills, city, stats, post grid
- ✅ Pet avatar upload — `AvatarService` compresses and uploads to Supabase Storage; `PetsService.addPet` / `updatePet` accept `avatarData` and persist `avatar_url`
- ✅ Avatar upload in editor — `ProfilePetEditorSheet` supports photo picker and passes `avatarData` through
- ✅ Avatar photo display in `PetProfileView` — `AsyncImage` loads from `pet.avatar_url`; falls back to species emoji on nil or load failure
- ✅ User avatar upload — `AvatarService.uploadUserAvatar`; displayed in `profileHeader` via `AsyncImage`; `PhotosPicker` in `ProfileAccountEditorSheet` (PR #12)
- 🔲 Pet-specific follow (follow a pet, not just a user) — current follow graph is user-to-user only

## Phase 5 — Messaging 🔲 Stub only

- `ChatListView` exists with hardcoded placeholder chat previews
- No backend, no service, no real data
- Requires Supabase Realtime or a messages table

## Phase 6 — Polish & Growth 🔲 Not started

- Push notifications (likes, comments, new followers)
- Onboarding flow for new users
- Feed algorithm (recency + social graph weighting)
- App Store assets, privacy policy, TestFlight beta
