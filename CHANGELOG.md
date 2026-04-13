# Changelog

All notable changes are documented here. Each entry corresponds to a merged PR and follows the [PR template](docs/pr-template.md).

Entries are in reverse chronological order.

---

## 2026-04-12 — Harden post image storage handling ([#10](https://github.com/halflkaka/pawpal/pull/10))

### Summary

Cleans up orphaned storage files when post creation rolls back or a post is deleted. Adds Supabase Storage RLS policies for the `post-images` bucket.

5 files changed, +150 / -22 lines.

### Changes

#### Bug Fixes
- **Storage rollback on create failure** — `createPost` tracks uploaded paths; on any failure after uploads have started, removes all successfully-uploaded objects before propagating the error
- **Storage cleanup on delete** — `deletePost` removes associated storage objects before deleting the DB row; `storagePathsForPost` resolves actual paths from post image URLs, with a folder-prefix fallback
- **Comment preview cleanup** — `deletePost` now clears `commentPreviews[postID]` to prevent stale data

#### Infra
- **`storagePathsForPost` helper** — parses public Supabase Storage URLs back to relative paths
- **`supabase/012_add_post_images_storage_policies.sql`** — RLS policies for the `post-images` bucket

### Files Changed

| Folder | Files |
|---|---|
| `PawPal/Services/` | `PostsService.swift` |
| `PawPal/Views/` | `CreatePostView.swift` |
| `supabase/` | `012_add_post_images_storage_policies.sql` |
| `docs/` | `known-issues.md` |

---

## 2026-04-12 — Remove duplicate feed avatar header ([#9](https://github.com/halflkaka/pawpal/pull/9))

### Summary

Removes a duplicate pet avatar and name block introduced during merge conflict resolution in PR #8. The `cardHeader` in `PostCard` was rendering both a standalone `petAvatarCircle` + `VStack` and the newer `petAvatarLink` wrapper.

1 file changed, +0 / -43 lines.

### Changes

#### Bug Fixes
- **Duplicate feed card header** — removed stale `petAvatarCircle` + name `VStack` from `cardHeader`; `petAvatarLink` is the correct single source

### Files Changed

| Folder | Files |
|---|---|
| `PawPal/Views/` | `FeedView.swift` |

---

## 2026-04-12 — Polish feed and profile UX ([#8](https://github.com/halflkaka/pawpal/pull/8))

### Summary

Adds inline comment previews to feed cards, smooths startup/auth transitions, and introduces direct delete for own posts and comments.

8 files changed, +420 / -84 lines.

### Changes

#### UI
- **Inline comment previews** — `PostCard` shows up to 2 recent comments inline (bold author name + content), a "查看全部 N 条评论" link, and an "添加评论…" prompt when empty
- **Smooth auth transitions** — `ContentView` and `AuthManager` reduce flash-of-wrong-screen on startup and sign-in/sign-out
- **Pet avatar in feed** — `petAvatarCircle` renders `AsyncImage` for `avatar_url` with emoji fallback

#### Features
- **Direct post/comment delete** — users can delete their own posts and comments from the feed and comments sheet; `CommentsView` gained per-comment delete

#### Performance
- **Comment preview tracking** — `PostsService` stores last 2 comment previews per post in a `@Published` dictionary so feed cards render them without extra queries

### Files Changed

| Folder | Files |
|---|---|
| `PawPal/Services/` | `AuthManager.swift`, `FollowService.swift`, `PostsService.swift` |
| `PawPal/Views/` | `CommentsView.swift`, `ContentView.swift`, `FeedView.swift`, `MainTabView.swift`, `ProfileView.swift` |

---

## 2026-04-12 — Pet-first discovery tab ([#7](https://github.com/halflkaka/pawpal/pull/7))

### Summary

Adds a tab switcher (动态 Posts | 宠物 Pets) to the Discover tab. The Pets tab loads all pets from Supabase, filters by species (6 options), and shows a 2-column card grid. Tapping a card navigates to `PetProfileView`. Completes Phase 3.

2 files changed, +168 / -5 lines.

### Changes

#### Features
- **Pets tab in Discover** — `ContactsView` gains a tab switcher; Pets tab loads all public pets via `loadAllPets()` and shows a 2-column `PetDiscoverCard` grid
- **Species filter** — 6-option filter row (全部, 狗狗, 猫咪, 兔子, 鸟类, 仓鼠); case-insensitive match against DB values
- **Error state** — network failures show a distinct ⚠️ state instead of a misleading empty state
- **Lazy loading** — pets only fetched on first tab switch; `isLoadingAll` guard prevents concurrent calls

#### Services
- **`PetsService.loadAllPets`** — queries all pets without owner filter (public RLS); sets `errorMessage` on failure

### Files Changed

| Folder | Files |
|---|---|
| `PawPal/Services/` | `PetsService.swift` |
| `PawPal/Views/` | `ContactsView.swift` |

---

## 2026-04-12 — Pet avatar upload and display ([#6](https://github.com/halflkaka/pawpal/pull/6))

### Summary

Users can now set a photo for each pet via an image picker in the pet editor. Photos upload to Supabase Storage and display in the feed card header and profile pet bubble band. Falls back to species emoji when no avatar is set.

5 files changed, +183 / -28 lines.

### Changes

#### Features
- **Pet avatar picker** — `ProfilePetEditorSheet` gains a `PhotosPicker` header; shows picked image → existing URL → species emoji fallback
- **Avatar upload** — `AvatarService` uploads to `{ownerID}/pet-avatar/{petID}.jpg`; resizes to 512px max edge at JPEG 0.82 quality; non-fatal (pet still saved if upload fails)
- **Avatar display in feed** — `petAvatarLink` in `PostCard` renders `AsyncImage` for `avatar_url` with emoji fallback
- **Avatar display in profile** — `petBubble` shows `AsyncImage` when `avatar_url` is set

#### Bug Fixes
- **Upload failure preserves existing avatar** — `updatePet` keeps the existing `avatar_url` if the new upload fails (was silently sending `null` to the DB)

#### Services
- **`AvatarService`** — new service for pet avatar upload
- **`PetsService`** — `addPet` and `updatePet` accept optional `avatarData`

### Files Changed

| Folder | Files |
|---|---|
| `PawPal/Services/` | `AvatarService.swift`, `PetsService.swift` |
| `PawPal/Models/` | `RemotePet.swift` |
| `PawPal/Views/` | `FeedView.swift`, `PawPalDesignSystem.swift`, `ProfileView.swift` |

---

## 2026-04-12 — Pet profile pages ([#5](https://github.com/halflkaka/pawpal/pull/5))

### Summary

Adds a dedicated `PetProfileView` so tapping a pet's avatar or name anywhere in the app opens a full pet profile page. Navigation wired via `NavigationLink(value:)` + `.navigationDestination(for: RemotePet.self)`.

4 files changed, +297 / -10 lines.

### Changes

#### Features
- **`PetProfileView`** — species emoji header, tag pills (species/breed/age/sex/weight), home city, bio, post count stat, 2-column post grid filtered by `pet_id`
- **Feed navigation** — tapping a pet avatar/name in `PostCard` pushes `PetProfileView`
- **Profile navigation** — pet bubble context menu "查看主页" navigates to `PetProfileView` (uses `@State` trigger — `NavigationLink` inside `.contextMenu` is broken on iOS)

#### Services
- **`PostsService.loadPetPosts`** — 4-level select fallback, dedicated `isLoadingPetPosts` flag, `refreshLikes` + `refreshCommentCounts` pass; `petPosts` cleared on `deletePost`

#### Models
- **`RemotePet`** — add `Hashable` conformance (required for `NavigationLink(value:)`)

### Files Changed

| Folder | Files |
|---|---|
| `PawPal/Services/` | `PostsService.swift` |
| `PawPal/Models/` | `RemotePet.swift` |
| `PawPal/Views/` | `FeedView.swift`, `PetProfileView.swift`, `ProfileView.swift` |

---

## 2026-04-12 — Docs: conventions, structure, and changelog ([#4](https://github.com/halflkaka/pawpal/pull/4))

### Summary

Establishes the project's documentation structure: PR template, testing guide, product vision, decisions log, known issues, scope, and database reference. Updates CLAUDE.md and ROADMAP.md to reflect current state.

22 files changed, +1469 / -276 lines.

### Changes

#### Docs
- **`docs/conventions/pr-template.md`** — PR description standard with section guide and example
- **`docs/testing.md`** — QA process: build, unit tests, UI tests, manual spot checks
- **`docs/product.md`** — product vision, target user, core principles
- **`docs/decisions.md`** — architectural and product decisions log
- **`docs/known-issues.md`** — known bugs and tech debt
- **`docs/scope.md`** — what is in scope, deferred, and off-limits
- **`docs/database.md`** — schema reference (renamed from `DB_SCHEMA.md`)
- **`CHANGELOG.md`** — retroactive entries for PRs #1–#3
- **`CLAUDE.md`** — updated with full conventions, agent workflow config, code conventions
- **`ROADMAP.md`** — updated to reflect actual current state per phase
- **`.claude/agents/dev-team.md`** — agent team role configs

### Files Changed

| Folder | Files |
|---|---|
| `docs/` | `database.md`, `decisions.md`, `known-issues.md`, `product.md`, `scope.md`, `testing.md` |
| `docs/conventions/` | `pr-template.md` |
| `.claude/agents/` | `dev-team.md` |
| (root) | `CHANGELOG.md`, `CLAUDE.md`, `ROADMAP.md`, `README.md` |

---

## 2026-04-12 — Fix like persistence across fresh sessions ([#3](https://github.com/halflkaka/pawpal/pull/3))

### Summary

Fixed like state not persisting after closing and reopening the app. Adds a likes rehydration pass after feed load and makes `RemoteLike` decoding tolerant of different Supabase payload shapes.

8 files changed.

### Changes

#### Bug Fixes
- **Like state persistence** — added rehydration pass from the likes table after posts load so previously liked posts remain liked across fresh sessions
- **RemoteLike decoding** — made decoder tolerant of different Supabase/PostgREST payload shapes instead of assuming one strict nested format

#### UI
- **ContactsView** — significant refresh of the discover screen
- **FeedView, ProfileView, CreatePostView** — incremental improvements to feed and profile surfaces

### Files Changed

| Folder | Files |
|---|---|
| `PawPal/Models/` | `RemotePost.swift` |
| `PawPal/Services/` | `FollowService.swift`, `PostsService.swift` |
| `PawPal/Views/` | `ContactsView.swift`, `CreatePostView.swift`, `FeedView.swift`, `MainTabView.swift`, `ProfileView.swift` |

---

## 2026-04-12 — Follow flow and engagement count stability ([#2](https://github.com/halflkaka/pawpal/pull/2))

### Summary

Fixes like/comment counts flashing to 0 on feed reload, fixes follow count staying at 0 on profile, and introduces a dedicated `FollowService` with full follow/unfollow/toggle support and feed filtering by followed users.

9 files changed.

### Changes

#### Features
- **FollowService** — new dedicated service with load, follow, unfollow, toggle, and feed-filter helpers
- **Follow-based feed filtering** — home feed can now scope to followed users plus self
- **Shared Supabase client** — `SupabaseConfig.client` added so all services share the same authenticated session, improving RLS consistency

#### Bug Fixes
- **Engagement count flash** — preserved known local like/comment state during async feed reloads to prevent counts briefly showing 0
- **Follow count on profile** — wired profile to load real follow data and bind stat to current following count

### Files Changed

| Folder | Files |
|---|---|
| `PawPal/Services/` | `AuthService.swift`, `FollowService.swift`, `PetsService.swift`, `PostsService.swift`, `ProfileService.swift`, `SupabaseConfig.swift` |
| `PawPal/Views/` | `CreatePostView.swift`, `FeedView.swift`, `ProfileView.swift` |

---

## 2026-04-11 — Performance improvements + UI upgrade ([#1](https://github.com/halflkaka/pawpal/pull/1))

### Summary

Performance and visual polish pass on the feed, create post, and profile screens. Fixes a batched query bottleneck that was firing N network calls per feed load, and upgrades key UI components to feel more premium and interactive.

9 files changed, +237 / -58 lines.

### Changes

#### Performance
- **Stable ForEach identity** — added `id: \.id` to feed post list so SwiftUI tracks posts by UUID; prevents full-list redraws when likes or comment counts update
- **Batched comment count refresh** — replaced per-post network loop with a single `.in()` query; reduces N round-trips to 1 after every feed load
- **Lazy image layout** — wrapped image sections in `LazyVStack` so layout is deferred until cards are near the viewport, reducing upfront rendering cost
- **Image grid computation** — extracted `GridItem` column array out of the view body into a helper method to avoid redundant recalculation on every render pass

#### UI
- **Post card depth** — added a dark gradient overlay at the bottom of post images to create visual depth and separate image from action row
- **Avatar ring** — added a subtle orange border around pet avatar circles in the feed to make cards feel more polished
- **Like button feedback** — like button now fires medium haptic on tap and switches to a red gradient capsule background when liked, making the interaction feel responsive
- **Mood emoji picker** — replaced free-text mood field with a horizontal emoji picker row (😊 😍 🤔 😴 🤩 😻 🥰 🎉); reduces friction and makes mood selection more visual
- **Image numbered badges** — image thumbnails in Create Post now show numbered badges (1, 2, 3...) so users know the upload order
- **Profile empty state** — replaced plain emoji + text with action cards (Create Post, Invite Friends) to give new users a clear next step
- **Tab switch haptics** — light haptic fires on every tab change, making navigation feel more native and tactile

#### Bug Fixes
- **Stale test import** — `PawPalTests` was importing `PetHealth` (old module name); updated to `PawPal` so unit tests compile and run correctly
- **URL validation** — `RemotePost.imageURLs` was accepting relative strings as valid URLs; now requires a valid scheme, fixing incorrect image rendering
- **Accessibility identifiers** — added identifiers to tab bar items and pet management buttons (`add-pet-button`, `save-pet-button`) so UI tests can reliably find elements

### Files Changed

| Folder | Files |
|---|---|
| `PawPal/Models/` | `RemotePost.swift` |
| `PawPal/Services/` | `PostsService.swift` |
| `PawPal/Views/` | `FeedView.swift`, `CreatePostView.swift`, `ProfileView.swift`, `MainTabView.swift`, `PawPalDesignSystem.swift` |
| `PawPalTests/` | `PawPalTests.swift` |

### Validations

- ✅ **Clean build** — no errors
- ✅ **Unit tests** — 5/5 pass
- ✅ **UI tests** — launch and performance tests pass
- ⚠️ **`testCanAddPetAndSeeItInProfilesAndHome`** — pre-existing gap; requires Supabase mock, not a regression
