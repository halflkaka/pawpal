# Changelog

All notable changes are documented here. Each entry corresponds to a merged PR and follows the [PR template](docs/pr-template.md).

Entries are in reverse chronological order.

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
