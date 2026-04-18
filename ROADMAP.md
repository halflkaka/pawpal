# PawPal Roadmap

## Current State

Phases 1, 2, and 3 are complete. Phase 4 is partial (pet-specific follow remains). Phase 5 is now visually complete (UI shipped in the 2026 refresh) but still needs a backend. Phase 6 is upcoming.

The 2026 visual refresh (April 2026) refactored every primary screen — Feed, Profile, Virtual Pet, Tab bar, Chat — against a new prototype. See `docs/decisions.md` for rationale.

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

## Phase 5 — Messaging ⚠️ UI only

- ✅ `ChatListView` redesigned — serif wordmark, cream search, online rail with DogAvatar bubbles, threaded rows with unread badges (April 2026 refresh)
- ✅ `ChatDetailView` new — sticky header, bubble groups with reaction overlay, "typing…" indicator, sticker tray, composer with accent send button
- 🔲 Real backend — still no messages table, no realtime subscription. Sample data is local-only and resets on relaunch
- 🔲 Read receipts / unread tracking against real data
- Requires Supabase Realtime or a messages table

## Phase 6 — Polish & Growth 🔲 Not started

- Push notifications (likes, comments, new followers)
- Onboarding flow for new users
- Feed algorithm (recency + social graph weighting)
- App Store assets, privacy policy, TestFlight beta
