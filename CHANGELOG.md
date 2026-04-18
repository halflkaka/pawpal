# Changelog

All notable changes are documented here. Each entry corresponds to a merged PR and follows the [PR template](docs/pr-template.md).

Entries are in reverse chronological order.

---

## 2026-04-18 — Chat entry points + follow lists + grid badge fix (#46)

## Summary

Follow-up fixes on top of #45 after the user reported two remaining gaps:

1. "The like was not showing completely in profile view post grid" — the badge fix in #45 (padding bump, dark pill) didn't fully land; on real image tiles the left half of the capsule was still clipping against the tile edge, leaving "2" visible but the heart + pill fragment gone.
2. "Currently there's no access to initiate a chat, also I can't see the list of who I'm following and who is following me" — #45 shipped the chat service + tables but left no UI for starting a thread, and the 粉丝 / 关注 stat cells on Profile were non-interactive.

4 files, +~380 / -~60 lines.

## Profile grid: like badge clipping fix

- Refactored `profilePostTile` in `ProfileView.swift` away from a single-overlay ZStack to two stacked overlays: (1) content layer (image or text tile) with its own `.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()`, (2) badge layer with `.overlay(alignment: .bottomLeading)` on the outer `Color.clear`.
- The ZStack approach was positioning the badge relative to the ZStack's effective bounds, which `scaledToFill` on the image could push past the tile frame — that's what sent the capsule into negative x on photo tiles. Anchoring the badge to the outer `Color.clear`'s bounds binds it to the 1:1 tile frame the grid allocated.
- Tuned padding from `.padding(8)` (uniform) to `.padding(.leading, 6).padding(.bottom, 6)` so the pill sits consistently flush with the bottom-left corner and can't visually collide with the next-row tile.

## Chat entry points

- `PetProfileView` now takes an optional `authManager: AuthManager?` param. Non-owner visitors on a pet page see a new "给主人发消息" accent-tinted pill below the avatar. Tapping it:
  - Calls `ChatService.shared.startConversation(viewerID, ownerID)` (idempotent — re-opens an existing thread if one exists).
  - In parallel, fetches the owner's `RemoteProfile` so the chat header renders with their avatar + handle immediately rather than blanking until the detail view fetches.
  - Pushes `ChatDetailView` via a `navigationDestination(item:)` bound to `@State pendingChatThread`.
  - Disables while in flight to block double-push.
- All `PetProfileView` call sites audited: `FeedView`, both destinations in `ProfileView`, and (new) `PostDetailView` all pass `authManager` through. `PostDetailView` picked up an optional `authManager` of its own and its three callers (`FeedView`, `ProfileView`, `PetProfileView`) pass theirs through too, so every navigation chain that ends at a pet page has the manager in scope. The only surface that intentionally hides the button is the owner viewing their own pet.
- Owner path is unchanged — the button only renders when `!canEdit && currentUserID != nil && authManager != nil && pet.owner_user_id != currentUserID`.

## Follow lists

- New `FollowListView.swift` — segmented `关注` / `粉丝` list with avatar + handle + display-name rows, each carrying a `发消息` shortcut pill that calls `ChatService.startConversation` and pushes `ChatDetailView`.
  - Self-rows don't get the message pill (you can't DM yourself).
  - Empty states carry mode-specific copy: 关注 nudges toward the 发现 tab; 粉丝 nudges toward posting.
  - Pull-to-refresh calls the matching `FollowService` loader.
- `FollowService` gained `loadFollowingProfiles(for:)` and `loadFollowerProfiles(for:)` — two-step queries (follows id list → `profiles in (...)` batch fetch) because the `follows → profiles` relationship isn't declared as a PostgREST FK hint.
- `ProfileView` wraps the 粉丝 / 关注 stat cells in `NavigationLink(value: FollowListDestination(mode:))` and adds a new `navigationDestination(for: FollowListDestination.self)` that constructs `FollowListView`. 帖子 / 宠物 stay plain taps — those surfaces already live on the Profile screen.

## Files Changed

| Area | File | Summary |
|---|---|---|
| Service | `PawPal/Services/FollowService.swift` | Added `loadFollowingProfiles` + `loadFollowerProfiles` + batch `fetchProfiles` helper |
| View | `PawPal/Views/FollowListView.swift` | New screen: segmented following/followers list with per-row DM shortcut |
| View | `PawPal/Views/ProfileView.swift` | Tile badge refactor; stat cells as `NavigationLink`; `FollowListDestination`; follow-list navigationDestination; pass `authManager` to `PetProfileView` |
| View | `PawPal/Views/PetProfileView.swift` | Optional `authManager` param; `给主人发消息` pill; `startChatWithOwner`; `pendingChatThread` + navigationDestination; pass `authManager` to `PostDetailView` |
| View | `PawPal/Views/PostDetailView.swift` | Optional `authManager` param + thread-through to `PetProfileView` |
| View | `PawPal/Views/FeedView.swift` | Pass `authManager` to both `PetProfileView` and `PostDetailView` |
| Docs | `CHANGELOG.md` | This entry |
| Docs | `docs/known-issues.md` | Close "chat entry points still missing" |

## Validations

- ⚠️ Build pending — sandbox lacks `xcodebuild`; needs local run per CLAUDE.md.
- Spot checks after build:
  - Profile grid: image tile with likes > 0 shows the full `♥ N` capsule, flush to the bottom-left corner, not clipped.
  - Profile stats row: tapping 粉丝 opens `FollowListView` on the followers tab; tapping 关注 opens it on the following tab. Toggle between the two via the top segmented control.
  - Follow list row: avatar + handle render; tapping 发消息 pushes `ChatDetailView`; self-row has no pill.
  - `PetProfileView` as non-owner: `给主人发消息` pill visible under the avatar; tap loads a spinner, then pushes into `ChatDetailView` with the partner avatar + handle populated.
  - `PetProfileView` as owner: no message pill (you don't DM yourself).
  - `PetProfileView` reached from `PostDetailView`: message pill renders (post → pet → DM path works).
  - Starting a chat to a user you've already messaged does not create a duplicate row — `startConversation`'s canonical-sorted SELECT returns the existing id.
  - Regression: Feed / Profile / Pet edit / Pet grid unchanged in layout and tap targets.

---

## 2026-04-18 — Chat MVP: real DMs, persisted virtual-pet stats, polish (#45)

## Summary

User reported five issues in one message:

1. "当 I click 喂食/玩耍, nothing happened, the stats did not change" — the stat bumps were ripped out in #44 (to fix sync drift) but the result was that the buttons became inert. User wanted the full game loop back.
2. "已经摸了 kaka X 下 is not synced in two places" — the tap-to-boop counter lived in `VirtualPetView`'s internal `@State`, so each screen kept its own count.
3. "In feed view, remove 0 count from the comment/like icon" — empty counts were visual noise.
4. "In profile view, the like is not showed completely for an image post" — heart badge on the grid tile clipped against the thumbnail edge.
5. "Can you implement the Chat view with real functionality instead of using fake data" — the entire chat tab was powered by `ChatSampleData` with a canned auto-reply timer.

All five addressed in a single PR because #1, #2, and #5 pull the same architectural lever (a shared store + real Supabase tables), and #3, #4 were tiny scoped polish fixes.

## Virtual pet: persisted stats + shared tap counter (#1, #2)

- New migration **016_pet_state.sql** (already landed) plus `VirtualPetStateStore` — a `@MainActor ObservableObject` singleton that owns two published dicts keyed by pet id: `tapCounts` (in-memory, session-scoped) and `petStates` (cached from the `pet_state` table).
- `VirtualPetView` now takes `petID: UUID?` and an `onAction: ((PetAction) -> Void)?`. With a real pet id it reads the tap counter from the store and routes feed/pet/play taps through the callback instead of mutating local state.
- `ProfileView` and `PetProfileView` wire `onAction` to `store.applyAction`, which optimistically bumps the cached snapshot and upserts `pet_state` (delta table: feed +15 hunger / +2 mood / +4 energy, play -4 hunger / +6 mood / -8 energy, pat +4 mood). Both screens prefer the persisted snapshot over the time-derived baseline for their `externalMood/Hunger/Energy` bindings, so the bar moves on tap *and* the sibling screen reflects the same value.
- Tap counter is now shared across views for the same pet id; previews with `petID: nil` fall back to a local `@State` counter so the preview sheet stays isolated.

## Chat MVP (#5)

- New migration **017_chat.sql** (already landed) introducing `conversations` and `messages` with canonical participant ordering, an after-insert trigger to maintain `last_message_preview / last_message_at`, and participant-scoped RLS on both tables.
- New `ChatService.shared` — loads threads (one SELECT on conversations + one SELECT on profiles for partner hydration, two queries total regardless of thread count), loads messages, sends text messages with optimistic local insert + rollback on failure, and starts new conversations with canonical participant sort + existing-row lookup to avoid redundant inserts.
- Rewrote `ChatListView` to render `ChatService.threads` with real partner avatars (`AsyncImage` on `profiles.avatar_url`, falling back to a coloured initial) and relative timestamps. The "在线" rail + online dots + unread badges are hidden — they weren't part of the MVP schema (see docs/scope.md).
- Rewrote `ChatDetailView` to render real `RemoteMessage` rows from the store, with optimistic send + inline error state when the write fails. Dropped sticker tray, reactions, and the canned auto-reply. Composer submits on Return or send-button tap; both paths use the same `ChatService.sendMessage`.
- `MainTabView` now passes `authManager` down into `ChatListView` so the service has a user id to scope reads by. Hardcoded `.badge(2)` removed from the chat tab — unread tracking needs a `last_read_at` column that isn't in the MVP schema.

## Feed: hide 0-counts on like/comment icons (#3)

- `FeedView.reactionRow` wraps the count `Text` in an `if post.likeCount > 0` and sets the HStack spacing to 0 when hidden, so a freshly-posted row reads as a clean icon instead of "❤ 0". Same for the comment pill.

## Profile grid: heart overlay no longer clips (#4)

- `profilePostTile` hides the badge capsule entirely when `post.likeCount == 0`, bumps inner vertical padding 3→5, outer padding 6→8, background opacity 0.38→0.45, and adds `.fixedSize(horizontal: true, vertical: false)` on the count `Text` so a three-digit count can't force the capsule to wrap inside the tile bounds.

~+900 / -430 lines across 10 files (new service files + chat rewrite + wire-through in profile screens).

## Files Changed

| Area | File | Change |
|---|---|---|
| DB | `supabase/015_pet_state.sql` | **New** — `pet_state` table + owner-write RLS for persisted mood / hunger / energy |
| DB | `supabase/016_chat.sql` | **New** — `conversations` + `messages` tables, canonical ordering, preview trigger, participant-scoped RLS |
| Services | `PawPal/Services/VirtualPetStateStore.swift` | **New** — shared store for tap counters + cached `pet_state` rows; `applyAction(_:petID:baseline:)` for the feed/pet/play game loop |
| Services | `PawPal/Services/ChatService.swift` | **New** — `loadThreads / loadMessages / sendMessage / startConversation`; `RemoteConversation`, `RemoteMessage`, `ChatThread` types |
| Views | `PawPal/Views/VirtualPetView.swift` | +`petID`, +`onAction` inputs; `effectiveTapCount` reads store when pet id is set; `feed/pat/play` route through `onAction` |
| Views | `PawPal/Views/ProfileView.swift` | Observe `VirtualPetStateStore.shared`; prefer persisted snapshot for external stat bindings; wire `onAction` to `store.applyAction`; lazy `loadIfNeeded` on appear |
| Views | `PawPal/Views/PetProfileView.swift` | Same pattern as `ProfileView`; `onAction` is only non-nil for the owner so visitors can't move the bars |
| Views | `PawPal/Views/ChatListView.swift` | Rewritten to render real `ChatThread`s from `ChatService`; removed `ChatSampleData`, online rail, unread badges; added empty state |
| Views | `PawPal/Views/ChatDetailView.swift` | Rewritten to render `[RemoteMessage]` from the cache; removed sticker tray / reactions / auto-reply; optimistic send with rollback + inline error |
| Views | `PawPal/Views/MainTabView.swift` | Pass `authManager` into `ChatListView`; remove hardcoded `.badge(2)` |
| Views | `PawPal/Views/FeedView.swift` | Hide like / comment count `Text` when count is 0; collapse HStack spacing |
| Docs | `docs/known-issues.md` | Close chat-is-fake and virtual-pet-stats-local entries; add DM-entry-point follow-up |
| Docs | `docs/scope.md` | Chat DMs move from "deferred" to "active"; sticker / reaction / realtime / unread stay deferred |
| Docs | `CHANGELOG.md` | This entry |

## Validations

⚠️ **Build pending** — `xcodebuild` not available in the agent environment. Exact command:

```
xcodebuild -project PawPal.xcodeproj -scheme PawPal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Spot checks (run after applying migrations 015 + 016):
- Virtual pet game loop: tap 喂食 in `ProfileView` → 饱食 bar jumps ~+15 → navigate into `PetProfileView` for the same pet → bar shows the *same* post-tap value, not the pre-tap baseline. Force-quit and reopen → the persisted value is still there.
- Tap counter: open `ProfileView`, tap the pet 3 times → label reads "已经摸了 X 3 下" → push into `PetProfileView` → same counter, continues to climb with further taps in either view.
- Play delta: 玩耍 decreases 活力 ~-8 and bumps 心情 ~+6; repeat play drops 活力 further, eventually saturating at 0 (CHECK constraint clamps server-side too).
- Visitor in `PetProfileView` (canEdit == false): 喂食 button fires the 🍖 + thought bubble but the bar doesn't move (server-side RLS would reject the write anyway, but we gate client-side to avoid a confusing optimistic bump).
- Chat inbox: open 聊天 tab with a fresh account → empty state "还没有对话". Seed a conversation directly in SQL `(INSERT INTO conversations (participant_a, participant_b) VALUES (...))` → tab now shows one row with the partner's username / avatar.
- Send a message: type in composer → tap send → bubble appears immediately (optimistic); kill network → send again → bubble rolls back and inline "发送失败" appears; restore network → send → bubble sticks.
- Feed row: a freshly-created post (0 likes, 0 comments) no longer shows "❤️ 0" / "💬 0" — just the icons. Add a like → count appears with proper spacing.
- Profile grid: a post with 100+ likes renders the heart badge cleanly without clipping against the tile edge.
- Existing flows unchanged: auth, feed load, create post, pet edit, dress-up accessory (from #43), stats sync (from #44) — all intact.

---

## 2026-04-18 — Sync virtual pet stats (mood / hunger / energy) across profile views (#44)

## Summary

User reported: "Now the dress up is in sync, but the stats of things like 活力 are not in." Follow-on from #43 — accessory now propagates cleanly between `ProfileView` and `PetProfileView`, but the three stat bars (心情 / 饱食 / 活力) were still drifting between the two screens.

Two feeding into each other:

1. **Same `@State` latching bug as accessory.** `VirtualPetView` owned `state.mood / state.hunger / state.energy` as internal `@State` seeded from the `state:` init param. SwiftUI reads a `@State`'s init value exactly once; subsequent parent re-renders with a freshly-computed `pet.virtualPetState(...)` were silently ignored. So whichever screen rendered first decided the bar values, and the sibling screen (or the same screen on pop-back) held onto its stale snapshot.

2. **Per-view mutation from feed / pet / play / tap.** Those buttons locally bumped `state.hunger`, `state.mood`, `state.energy` inside a single view. A tap in `ProfileView` would never reach `PetProfileView`, so actions in one screen guaranteed visible divergence.

Fix: apply the exact same controlled-input pattern that fixed accessory in #43, and remove the per-view mutations so the bars stay purely derived from (posts + time).

- New `externalMood: Int?`, `externalHunger: Int?`, `externalEnergy: Int?` inputs on `VirtualPetView`. Both profile screens bind them to the output of a single shared `pet.virtualPetState(stats:posts:)` computation.
- Inside `VirtualPetView`, three `.onChange(of:initial:)` blocks mirror the incoming ints into `state.mood / state.hunger / state.energy` with a light ease-out animation. `initial: true` seeds on first appear so the two screens can't disagree even on a single render pass.
- Call sites compute `let vpState = pet.virtualPetState(...)` once and reuse it for both the `state:` seed and the external bindings so the state init and the external inputs are guaranteed to read the same (posts + time) snapshot.
- `feed / pet / play / tapPet` no longer mutate stat values — they still drive the reaction emoji, thought bubble, and jump animation, which are transient UI that's fine to stay view-local. This is the right tradeoff because the bars are meant to represent derived state (recent post activity, time of day), not a toy counter per screen.

~+50 / -20 lines across 3 files.

## Files Changed

| Area | File | Change |
|---|---|---|
| Views | `PawPal/Views/VirtualPetView.swift` | +`externalMood / externalHunger / externalEnergy` inputs; three `.onChange(of:initial:)` syncs; remove stat mutations from `feed / pat / play / tapPet` |
| Views | `PawPal/Views/ProfileView.swift` | Compute `vpState` once; pass `externalMood / externalHunger / externalEnergy` to `VirtualPetView` |
| Views | `PawPal/Views/PetProfileView.swift` | Same as `ProfileView` |

## Validations

⚠️ **Build pending** — `xcodebuild` not available in the agent environment. Exact command:

```
xcodebuild -project PawPal.xcodeproj -scheme PawPal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Spot checks:
- Open `ProfileView` → note 心情 / 饱食 / 活力 values → navigate into `PetProfileView` for the same pet → the three bars show the **same** numbers (allowing ±1 across a minute boundary since 活力 is time-of-day derived).
- Tap 喂食 / 摸摸 / 玩耍 in `ProfileView` → bars no longer jump locally (expected — they're derived now). The 🍖 / ✨ / 🎾 emoji, the thought bubble update, and the jump animation still fire as interaction feedback.
- Navigate back and forth between the two screens: stats remain stable at the derived value, no per-screen drift.
- Create a new post for the pet → return to `ProfileView` → stats recompute (post count changed → 心情 baseline rises via `PetStats.derivedHappiness`, 饱食 resets to ~100 since `lastPostAt` is now).
- Accessory sync from #43 still works (no regression): 🎩 on `ProfileView` → pop into `PetProfileView` → hat is present.

---

## 2026-04-18 — VirtualPetView controlled-accessory input (#43)

## Summary

User reported: "the virtual pet state in pet profile view is not maintained. Every time I go back to pet profile view the virtual pet is reset. And it is different from the one in normal profile view."

Two separate but related bugs:

1. **Virtual pet reset on every pop-back.** `PetProfileView.refreshPetIfNeeded` was bumping `petReloadSeed` *unconditionally* after a successful cache/DB read (the "just bump it, it's cheap" approach we landed in #41). That forced `VirtualPetView` to re-init on every `.task`, which runs on every appear — including pop-backs from `PostDetailView`. The re-init wiped the view's internal `@State`: thought bubble reset to a random initial, `tapCount` went to 0, breathing animation restarted. Visible to the user as "the virtual pet is reset every time I go back."

2. **ProfileView and PetProfileView could still drift.** `VirtualPetView` owned `state.accessory` as internal `@State`, which SwiftUI only reads from its init value once. Any subsequent accessory change that came in via a new init pass (e.g. parent re-rendered with updated `pet.accessory` from the shared cache) was silently ignored by the live view. So dressing up in `PetProfileView` updated the cache, but `ProfileView`'s `VirtualPetView` — still alive on the navigation stack above — kept showing the pre-change accessory when the user popped back to it.

Fix in one architectural move: make the accessory a **controlled input** on `VirtualPetView`.

- New `externalAccessory: DogAvatar.Accessory?` input on `VirtualPetView`. Parents (`ProfileView`, `PetProfileView`) bind it to `DogAvatar.Accessory(rawValue: pet.accessory ?? "none")`.
- Inside `VirtualPetView`, a `.onChange(of: externalAccessory, initial: true)` syncs the incoming value into `state.accessory` with a spring animation. This is the mechanism that lets cross-view changes flow in without a re-init — `@State` stays, internal state (thoughts / tapCount / breathing phase) survives, and the hat just animates on.
- Removed `petReloadSeed` from `PetProfileView` entirely — the re-init hack is no longer needed. Also simplified `refreshPetIfNeeded` (no more diagnostic prints, no conditional seed bump logic).
- `PetProfileView`'s `VirtualPetView.id(pet.id)` now resets only when the pet itself changes, not on accessory tweaks.

~+55 / -70 lines across 3 files.

## Files Changed

| Area | File | Change |
|---|---|---|
| Views | `PawPal/Views/VirtualPetView.swift` | +`externalAccessory: DogAvatar.Accessory?` input; `.onChange(of:initial:)` syncs it into `state.accessory` with spring animation |
| Views | `PawPal/Views/ProfileView.swift` | Pass `externalAccessory:` to `VirtualPetView` so cross-view changes animate back here |
| Views | `PawPal/Views/PetProfileView.swift` | Pass `externalAccessory:`; remove `petReloadSeed`; revert `.id` to `pet.id`; simplify `refreshPetIfNeeded` |

## Validations

⚠️ **Build pending** — `xcodebuild` not available in the agent environment. Exact command:

```
xcodebuild -project PawPal.xcodeproj -scheme PawPal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Spot checks:
- Dress up pet in `ProfileView` (tap 🎩) → navigate into `PetProfileView` → hat is present on first appear (correct).
- Continue tapping around inside `PetProfileView` (boop the pet a few times to build tap count, wait for the thought bubble to rotate). Navigate back to `ProfileView` → return to `PetProfileView`: tap count and thought bubble **persist**; no animation restart; no "reset" feeling.
- In `PetProfileView`, swap accessory (hat → bow). Pop back to `ProfileView` without killing the screen: the virtual pet on `ProfileView` now shows the bow, animated via spring transition. No full re-init — breathing stays, thought stays.
- Switch to a different active pet in `ProfileView` → `.id(pet.id)` kicks in → virtual pet reinitializes cleanly (expected behavior).
- Non-owner opens someone else's pet in `PetProfileView`: accessory chips are inert (no callback wired), accessory renders from the owner's `pets.accessory` via the same `externalAccessory` path.

---

## 2026-04-18 — Shared PetsService + optimistic accessory writes (#42)

## Summary

Third and final pass on the cross-view accessory sync bug. After #40 and #41 the user was *still* seeing "the virtual pet in pet profile and the normal profile is still not in sync." The prior fixes addressed the view-level plumbing (reload seeds, unconditional re-init, `fetchPet` on appear), but missed the actual root cause: `ProfileView` and `PetProfileView` each held their own `@StateObject private var petsService = PetsService()`. Two isolated caches + a race window between the nav push and the DB write meant the pet-profile screen could read `accessory = nil` from Supabase *before* the profile screen's write had landed, then render bare-headed.

Architectural fix in three moves:

1. **`PetsService.shared` singleton** — one cache app-wide. Optimistic local updates in any view are immediately observable from any other view. `@ObservedObject` instead of `@StateObject` in both screens so we don't recreate the service on remount.

2. **Optimistic `updatePetAccessory`** — we now mutate the local cache *before* awaiting the DB write, with a rollback on failure. This means that by the moment `ProfileView` fires `onAccessoryChanged` (and before the nav push to `PetProfileView` even completes), the shared cache already reflects the hat. The read-after-write race is closed at the cache layer.

3. **Cache-first `refreshPetIfNeeded`** — `PetProfileView` now checks `PetsService.shared.cachedPet(id:)` *before* going to the DB. For the owner's own pet — which is always in the cache after `loadPets` — the accessory is applied synchronously on appear. The DB fetch still runs in the background for boop counts / cross-device changes, but a stale DB read cannot clobber a fresh optimistic write (the merge prefers the non-nil cache value over a nil DB value).

~+55 / -25 lines across 3 files.

## Files Changed

| Area | File | Change |
|---|---|---|
| Services | `PawPal/Services/PetsService.swift` | Added `static let shared`; added `cachedPet(id:)`; made `updatePetAccessory` optimistic with rollback |
| Views | `PawPal/Views/ProfileView.swift` | Switched from `@StateObject` to `@ObservedObject private var petsService = PetsService.shared` |
| Views | `PawPal/Views/PetProfileView.swift` | Switched to `PetsService.shared`; `refreshPetIfNeeded` now cache-first, then DB with merge that preserves non-nil cached accessory over stale DB nil |

## Validations

⚠️ **Build pending** — `xcodebuild` not available in the agent environment. Exact command:

```
xcodebuild -project PawPal.xcodeproj -scheme PawPal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Spot checks:
- Owner in `ProfileView` taps 🎩 on the virtual pet → navigates into `PetProfileView` → hat is present on first appear (no flash of bare head). Xcode console: `[PetProfileView] refreshPetIfNeeded(cache): accessory old=... new=hat`
- Owner in `PetProfileView` taps 🎩 on the virtual pet → navigates back to `ProfileView` → hat is present (the cache already reflects it; pops don't rebuild parent views but `activePet` re-renders from the updated `@Published` cache)
- Other profile tabs that read `petsService.pets` (editing, deletion, avatar changes) continue to function — the shared singleton uses the same publish/observe contract
- Open another user's pet via Feed: cache miss → DB fetch path runs; no crash; accessory renders from the DB row

---

## 2026-04-17 — Uniform grid tile size + robust cross-view accessory sync (#41)

## Summary

Two follow-ups to #40, both from the same user-reported session:

1. **Grid tiles were visibly different sizes.** The image tile had an edge-to-edge 150pt photo and natural-height footer, while text tiles had `minHeight: 210` with `maxHeight: .infinity`. The image tile ended up shorter than the text tiles beside it ("grid size of the one with image is different than the others"). Fix: enforce one shared outer tile height (220pt), inset the photo (10pt padding) and shrink it to 110pt so it reads as a thumbnail inside a 220pt card instead of dominating the top half, and give the caption area the same footprint as the text tile's content area so the two recipes compose to identical outer dimensions.

2. **Cross-view accessory sync still missing the hat.** Despite #40's `fetchPet` + reload-seed pattern, the user reported "I added hat to the normal profile but when go back to pet profile it is gone". Root cause was defensive: our comparison only bumped the seed when `fresh.accessory != pet.accessory`, but there are cases where the nav-passed snapshot already carried the fresh value (ProfileView's cache had already been updated post-write), so `old == new` and the seed didn't bump — yet `VirtualPetView`'s `@State` had already latched onto a different init-time value further down the render cascade. Fix: unconditionally bump the seed whenever `refreshPetIfNeeded` succeeds. Cost is one re-init per mount (~16ms, breathing animation restarts once); benefit is that the hat/bow/glasses cannot silently disappear on nav. Also added a `print` in `refreshPetIfNeeded` so future investigations can confirm what the DB returned.

~+40 / -25 lines across 1 file.

## Files Changed

| Area | File | Change |
|---|---|---|
| Views | `PawPal/Views/PetProfileView.swift` | Unified tile height constant; image tile inset + 110pt thumbnail; refresh always bumps reload seed; diagnostic print in `refreshPetIfNeeded` |

## Validations

⚠️ **Build pending** — `xcodebuild` not available in the agent environment. Exact command:

```
xcodebuild -project PawPal.xcodeproj -scheme PawPal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Spot checks:
- Grid of mixed tile types (at least one image post + 2-3 text-only posts): all tiles are the same outer dimensions (220pt tall); image tile has an inset thumbnail, text tile is solid cream
- Text tile's caption area starts at the top (quote glyph + caption); counts sit at the bottom
- Image tile's caption area is roughly half the tile height; counts sit below caption
- Owner taps 🎩 in `ProfileView` → navigates into `PetProfileView` → hat is present (not gone). Check the Xcode console for `[PetProfileView] refreshPetIfNeeded: accessory old=... new=hat` — if the log shows `new=none`, the DB write from `ProfileView` never landed (migration 014 probably not applied)
- In-view accessory tap on `PetProfileView` still works — breathing/tail animations briefly pause on the initial mount (seed bump) but don't restart on subsequent chip taps
- Pull-to-refresh on `PetProfileView` also picks up any cross-view accessory change

---

## 2026-04-17 — Cross-view accessory sync on PetProfileView (#40)

## Summary

Follow-up to #39. User reported: "the virtual pet in pet profile and normal profile is not synced up. I added hat to the normal profile but when go back to pet profile it is gone."

Root cause: each profile screen owns its own `PetsService` instance (separate caches) and `PetProfileView`'s `@State var pet` is seeded once from the navigation argument. Dressing up in `ProfileView` wrote the new accessory to Supabase, but when the user then navigated into `PetProfileView`, the latter was still rendering its stale snapshot — its virtual pet re-init read `pet.accessory` (which was `nil`/stale) and bare-headed won.

Fix in three parts:

1. **Single-pet refresh in `PetsService`.** New `fetchPet(id:)` re-reads one row from Supabase — smaller round-trip than `loadPets(for: ownerID)` and doesn't disturb the cached list. Callers get back an optional `RemotePet` or nil on failure so their existing snapshot survives a transient error.

2. **Refresh in `PetProfileView.task`.** Added `refreshPetIfNeeded()` which calls `fetchPet`, overwrites `@State var pet`, and compares the new vs. old `accessory` / `avatar_url`. Runs in both `.task` (first appear) and `.refreshable` (pull-to-refresh).

3. **Targeted re-init via a reload seed.** `VirtualPetView`'s `.id` was `.id(pet.id)` — stable within a view's lifetime so the breathing/tail animations don't reset on every in-view accessory tap. That stability was also why the cross-view refresh didn't force a re-init. Added `@State petReloadSeed: Int` that the refresh bumps **only when the accessory (or avatar_url) actually differs**; the id becomes `.id("\(pet.id)-\(petReloadSeed)")`. Cross-view change → re-init; in-view tap → no re-init → animations keep playing.

The reverse direction (dress up in `PetProfileView`, navigate back to `ProfileView`) is a known follow-up: `ProfileView.loadAll()` is called from `.task` which in SwiftUI only fires on first attach, not on pop. Tracked in known-issues.

~+30 / -4 lines across 2 files.

## Files Changed

| Area | File | Change |
|---|---|---|
| Services | `PawPal/Services/PetsService.swift` | +`fetchPet(id:)` (single-pet refresh) |
| Views | `PawPal/Views/PetProfileView.swift` | +`petReloadSeed`, +`refreshPetIfNeeded()`, wired into `.task` + `.refreshable`, `VirtualPetView.id` includes seed |

## Validations

⚠️ **Build pending** — `xcodebuild` not available in the agent environment. Manual simulator run needed before shipping. Exact command:

```
xcodebuild -project PawPal.xcodeproj -scheme PawPal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Spot checks:
- Owner taps 🎩 on virtual pet in `ProfileView` → navigates into `PetProfileView` → hat appears immediately (not bare-headed)
- Owner in `PetProfileView` taps 🎀 chip → breathing / tail animations do NOT restart (in-view tap doesn't bump the seed)
- Pull-to-refresh on `PetProfileView` also picks up any cross-view accessory change
- Non-owner opens `PetProfileView` after owner changed accessory elsewhere → sees the latest accessory
- Reverse direction (dress up in `PetProfileView`, back to `ProfileView`) — confirm whether this is still stale; if so, file as issue

---

## 2026-04-17 — Persisted accessory + time-based mood/hunger/energy + distinct tile silhouettes (#39)

## Summary

Three follow-ups to #37 / #38, all driven by user feedback:

1. **Text & image post tiles were visually indistinguishable** in the `PetProfileView` grid — both used the same "edge-to-edge hero on top, white footer below" recipe, and side-by-side they read as one continuous block. Split the recipes: text-only tiles are now one solid cream card with the counts inline at the bottom; image tiles keep the photo + white footer. Grid spacing bumped 10 → 12 for breathing room.

2. **Virtual pet dress-up state reset on every revisit.** The accessory (🎀 / 🎩 / 👓) was local `@State` on `VirtualPetView`, so a pet dressed up in one session was bare-headed on the next. Added `pets.accessory` (migration 014 with a CHECK constraint restricting values to `'none' / 'bow' / 'hat' / 'glasses'`), a `updatePetAccessory` service method, and wired `onAccessoryChanged` on both `PetProfileView` and `ProfileView` to persist. Owner-only — visitors can toggle locally but the RLS policy rejects their write.

3. **Mood / hunger / energy are now time-aware.** Previously all three were pure functions of post count. Now:
   - **Hunger** treats each post as a "meal event": 100 right after a post, decays ~3pt/hour, floors at 20. Pets with no posts sit neutral at 60.
   - **Energy** follows a circadian sine: peaks ~90% mid-afternoon, dips ~25% overnight, smooth across minutes.
   - **Mood** starts from the post-derived happiness baseline and decays −1pt per 6 hours since last post, floor 30.

   A visitor opening the same profile at midnight vs. 2pm now sees a genuinely different virtual pet.

1 new SQL migration, 1 new model field, 1 service method, 2 views + 2 models touched. ~+180 / -40 lines.

## Files Changed

| Area | File | Change |
|---|---|---|
| Migrations | `supabase/014_add_pets_accessory.sql` | New: adds `pets.accessory` + CHECK constraint |
| Models | `PawPal/Models/RemotePet.swift` | +`accessory: String?` field |
| Models | `PawPal/Models/RemotePet+VirtualPet.swift` | Seed accessory + pass `posts` / `now` to stat helpers |
| Models | `PawPal/Models/PetStats.swift` | New `lastPostAt(in:)` helper |
| Models | `PawPal/Models/RemotePet+VirtualPet.swift` | Replace `derivedHunger(for:)` / `derivedEnergy(for:)` with time-based versions; add `decayedMood(base:lastPostAt:now:)` |
| Services | `PawPal/Services/PetsService.swift` | +`updatePetAccessory(petID:ownerID:accessory:)` |
| Views | `PawPal/Views/PetProfileView.swift` | Tile recipe split (imageTile / textOnlyTile) + `persistAccessory` wiring + grid spacing 10→12 |
| Views | `PawPal/Views/ProfileView.swift` | `onAccessoryChanged` persists to Supabase + `posts:` passed to `virtualPetState` |
| Docs | `docs/known-issues.md` | Migration 014 gate + spot-check list |

## Validations

⚠️ **Build pending** — `xcodebuild` not available in the agent environment. Manual simulator run + spot checks required before shipping. Exact command:

```
xcodebuild -project PawPal.xcodeproj -scheme PawPal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Spot checks:
- Apply migration 014 in Supabase SQL editor first
- Tap 🎩 on your own pet → navigate away → return: hat still on
- Visit mid-afternoon: 活力 bar reads ~85-90%; visit at 2am: ~25%
- Pet with fresh post: 饱食 near 100%; pet without posts in 24h: ~28%
- Text post tile sits next to image tile in the grid — two distinct silhouettes (solid cream block vs. photo + white strip), not one continuous block
- Non-owner can still toggle accessory locally but it doesn't survive a revisit (RLS rejects the write)

---

## 2026-04-17 — PetProfileView: shared boops + unique-per-day visit counter (#38)

## Summary

User ask: "I want the functionality that any visitor of the pet profile can interact with the virtual pet, and there should be a tracker count of total visits in the pet profile."

The tap-to-boop interaction was already open to any visitor at the UI level after #37, but the boop count only existed as local state that reset on navigation — there was no social proof of "N people have booped this pet" across sessions. There was also no visit tracker of any kind.

Added two engagement primitives:

1. **Shared boop counter** — when a non-owner taps the pet character in `VirtualPetView`, the tap is buffered locally (for instant UI feedback) and flushed to a server-side `pets.boop_count` via a debounced RPC. Multiple taps inside a short window coalesce into one RPC call so we don't hammer Supabase.
2. **Unique-per-day visit tracker** — opening a pet profile writes one row to a new `pet_visits` table keyed on `(pet_id, viewer_user_id, visited_on)`. A same-day refresh is deduped by the primary key; a return visit on a new day adds to the count. Owners' own views don't count (client-side filter).

Both counts show in the stats card as three columns: `帖子 / 访客 / 摸摸`.

Per the scope answered in the clarifying questions:
- Interaction persistence: **boop count only** (hunger/energy stay local/decorative, per the existing entry in `docs/known-issues.md`)
- Visit counting: **unique per day** (not total views, not unique-ever)
- Owner self-views: **excluded**
- Display: **stats card, three columns**

1 new SQL migration, 1 new model field, 1 service extension, 2 views touched. Total ~+380 / -30 lines.

## Changes

### `supabase/013_pet_visits_and_boops.sql` (new file, +95 lines)
- New `pet_visits` table: `(pet_id, viewer_user_id, visited_on, first_visited_at)`. Primary key on the first three columns, so `INSERT ... ON CONFLICT DO NOTHING` naturally dedupes same-day refreshes. Cascades on `pets` delete and `auth.users` delete.
- New `pets.boop_count integer not null default 0` column.
- New `increment_pet_boop_count(pet_id uuid, by_count integer default 1)` RPC. `security definer` + grant to `authenticated` so any signed-in visitor can boop without needing update permission on the `pets` table. Guards against null/negative deltas.
- RLS on `pet_visits`: anyone can read totals; users can only insert their own rows.

### `Models/RemotePet.swift` (+6 lines)
- Added optional `var boop_count: Int?` field. Optional so rows from before migration 013 — or selects that don't include the column — still decode.

### `Services/PetsService.swift` (+100 lines)
- `recordVisit(petID:viewerUserID:ownerID:)` — upserts a `pet_visits` row with `onConflict:ignoreDuplicates:`. Silently skipped when viewer == owner. Analytics-style: failures log but never surface to the UI.
- `fetchVisitCount(petID:)` — returns `COUNT(*) from pet_visits where pet_id = ?` via `select("*", head: true, count: .exact)`.
- `incrementBoopCount(petID:by:)` — calls the `increment_pet_boop_count` RPC and returns the new server-side count so the caller can reconcile its optimistic state.
- `fetchBoopCount(petID:)` — selects `boop_count` from the pet row.

### `Views/VirtualPetView.swift` (+12 lines)
- New optional `onBoop: (() -> Void)?` callback fired from `tapPet()` after the local state update. Owner screens (ProfileView) leave it nil; the public `PetProfileView` wires it up.

### `Views/PetProfileView.swift` (+180 / -15 lines)
- New state: `visitCount`, `serverBoopCount`, `pendingBoopDelta`, `boopFlushTask`, plus a `boopFlushDelay` constant (1.8s).
- `.task` now loads engagement counts and records a visit alongside loading posts. `.refreshable` does the same so pull-to-refresh keeps the stats honest. `.onDisappear` flushes any buffered boops so the last few taps before navigation survive.
- Stats card expanded from one column (帖子) to three: `帖子 / 访客 / 摸摸`, each a `statCell(value:label:)` separated by a thin hairline `statDivider()`. Values use `.contentTransition(.numericText())` for a subtle roll when they update.
- `virtualPetBoopHandler` computed property returns nil for owners, a real handler for everyone else — wired into `VirtualPetView.onBoop`.
- `handleBoop()` increments `pendingBoopDelta` immediately (so the `摸摸` cell rolls up instantly) and arms the debounce via `scheduleBoopFlush()`.
- `scheduleBoopFlush()` cancels any pending task and starts a new `Task { @MainActor in ... }` that waits `boopFlushDelay` seconds then calls `flush()`. Cancellation is key — without it, a 10-tap burst would schedule 10 flushes instead of coalescing.
- `flushPendingBoops()` runs synchronously on disappear; `flush()` is the async version that actually calls the RPC and reconciles the server count. On failure, the delta rolls back so a retry on the next flush can pick it up.
- `formatCount(_)` helper renders counts > 1000 as "1.2k" so the three-column layout stays readable.

## Files Changed

| File | +/− |
|---|---|
| `supabase/013_pet_visits_and_boops.sql` | new (+95) |
| `PawPal/Models/RemotePet.swift` | +6 / -1 |
| `PawPal/Services/PetsService.swift` | +100 / -0 |
| `PawPal/Views/VirtualPetView.swift` | +12 / -0 |
| `PawPal/Views/PetProfileView.swift` | +180 / -15 (≈) |
| `CHANGELOG.md` | this entry |
| `docs/known-issues.md` | spot-check addendum for #38 |
| `docs/database.md` | pet_visits + boop_count documentation |

## Validations

- ❓ `xcodebuild` — not available in authoring sandbox; **build verification still pending**
- ⚠️ **Migration must be run** in the Supabase dashboard before the app exercises these flows. If the migration hasn't run, `recordVisit` / `incrementBoopCount` / `fetchBoopCount` will all fail silently (logged; UI falls back to zeros).
- ⚠️ Manual spot-checks pending:
  - Stats card shows three columns: 帖子 N | 访客 M | 摸摸 K
  - Open your own pet → 访客 does not increment (self-views excluded), 摸摸 doesn't increment when you tap the pet (owner's boops are local only — onBoop is nil)
  - Open another user's pet for the first time today → 访客 increments by 1; refresh the page and it doesn't double-count; next day, visiting again adds another 1
  - Tap the pet rapidly 10 times → 摸摸 cell rolls up immediately by 10 (optimistic); after ~1.8s idle, one RPC fires; server count matches; navigate away during a burst and `.onDisappear` still flushes
  - If the server call fails, the optimistic count rolls back cleanly (no ghost count)
  - Counts > 1000 render as "1.2k" / "12.5k" — the three cells stay on one row even on small devices
  - RLS: try to insert a visit as a different viewer_user_id via the API → rejected
  - Delete a pet → `pet_visits` rows for that pet are cascade-deleted
- ✅ Schema: Migration 013 is backwards-compatible — no changes to existing tables other than the new nullable-defaulted column
- ✅ Not breaking: `ProfileView`'s featured pet section continues to call `VirtualPetView(state:)` without an onBoop, and the virtual pet still works there (no regression on owner flow)

---

## 2026-04-17 — PetProfileView: add interactive virtual pet + changeable avatar (#37)

## Summary

Two asks, one PR: (1) the interactive virtual-pet stage (feed/pet/play, stats bars, thought bubble, tap-to-boop) previously only appeared on the owner's `ProfileView`; when you tapped into a pet from the feed / contacts / search you landed on a read-only `PetProfileView` with no interactive element. (2) The pet's profile photo on `PetProfileView` had no edit affordance — changing it required leaving the screen and going through the dedicated edit-pet sheet on `ProfileView`.

Fixed both. The same `VirtualPetView` now renders inside `PetProfileView`'s header (seeded from the pet's own posts via `PetStats.make`), and owners see a camera badge on the avatar that opens `PhotosPicker` for in-place photo change. Non-owners see the stage (so a cat's page still shows the full interactive experience) but no edit affordance on the avatar.

Along the way the virtual-pet seeding logic was extracted from `ProfileView` into a `RemotePet` extension (`RemotePet+VirtualPet.swift`) so both screens are guaranteed to stay in lock-step — no more "cat got the new feature on one screen but not the other" like the #35 incident.

4 files changed, ~+320 / -130 lines.

## Changes

### `Models/RemotePet+VirtualPet.swift` (new file, +130 lines)
- New extension on `RemotePet` exposing `chineseBreed`, `formattedAge`, `virtualPetBackground`, and `virtualPetState(stats:)` — the same seeding logic that used to live as private methods on `ProfileView`.
- New static helpers on `PetStats`: `derivedHunger(for:)`, `derivedEnergy(for:)`, `initialThought(for:stats:)`.
- File-level doc comment explains why the helpers moved — avoiding the drift that caused #35 (second call-site forgot to pass `species`).

### `Views/ProfileView.swift` (−115 lines)
- `featuredPetSection` collapsed from a 20-line `VirtualPetState(...)` initializer call to `VirtualPetView(state: pet.virtualPetState(stats: activePetStats))`.
- Deleted the now-duplicated private helpers (`chineseBreed(for:)`, `formattedAge(for:)`, `virtualPetBackground(for:)`, `derivedHunger(for:)`, `derivedEnergy(for:)`, `initialThought(for:stats:)`).

### `Views/PetProfileView.swift` (+220 / -15 lines)
- Converted `pet` from `let` to `@State` so the avatar URL can be refreshed in-place after a successful upload.
- Added `@StateObject var petsService`, plus `pickedAvatarItem / pickedAvatarPreview / isUploadingAvatar / avatarErrorMessage` to drive the picker.
- `canEdit` computed: true iff `pet.owner_user_id == currentUserID`.
- `petAvatar`: added a preview-first cascade (local preview → remote URL → species emoji fallback) plus a dimming + spinner overlay while the upload is in flight.
- New `avatarWithEditAffordance`: wraps `petAvatar` in a `PhotosPicker` + camera-badge overlay when `canEdit`; plain avatar otherwise.
- New `handlePickedAvatar(_:)`: loads the picked `Data`, sets a local `Image` preview immediately, uploads via `PetsService.updatePetAvatar`, on success commits the new URL to `pet.avatar_url` and clears the preview, on failure surfaces a short Chinese error message and keeps the previous avatar.
- `petHeader`: inserted a `VirtualPetView(state: pet.virtualPetState(stats: PetStats.make(from: postsService.petPosts)))` between the bio and the stats card. `.id(pet.id)` resets internal animation state when navigating between pets.
- Added `"点击头像更换照片"` helper caption (owners only).

### `Services/PetsService.swift` (+30 lines)
- New `updatePetAvatar(_ pet:, for userID:, data:)` method — uploads via `AvatarService.uploadPetAvatar`, patches only `avatar_url` on the pet row, and returns the new URL. Also keeps the cached `pets` array in sync if the pet is present. Avoids the heavier `updatePet` full-record round-trip for the "just change the photo" flow.

## Files Changed

| File | +/− |
|---|---|
| `PawPal/Models/RemotePet+VirtualPet.swift` | new (+130) |
| `PawPal/Views/PetProfileView.swift` | +220 / -15 (≈) |
| `PawPal/Views/ProfileView.swift` | +8 / -115 (≈) |
| `PawPal/Services/PetsService.swift` | +30 / -0 |
| `CHANGELOG.md` | this entry |
| `docs/known-issues.md` | spot-check addendum for #37 |

## Validations

- ❓ `xcodebuild` — not available in authoring sandbox; **build verification still pending**
- ⚠️ Manual spot-checks pending:
  - Tap into your own pet from the Profile list → `PetProfileView` shows the full VirtualPetView stage (stats bars, feed/pet/play, thought bubble, tap-to-boop) in the header.
  - Tap into the same pet from the Feed → same stage, same seeded values (`PetStats.make` produces identical results).
  - Avatar on your own pet shows the orange camera badge in the bottom-right. Non-owner pets show no badge.
  - Tap the avatar (owner) → `PhotosPicker` opens. Pick a photo → preview appears immediately in the circle, dimming + spinner overlays during upload, camera badge fades while `isUploadingAvatar` is true.
  - On success → preview clears, new avatar_url renders via `AsyncImage`, parent `ProfileView` also reflects the change (because `PetsService` cached `pets` array is patched).
  - On failure → preview clears, previous avatar_url shown, red error caption "上传失败,请再试一次" appears under the avatar.
  - Virtual pet on `PetProfileView` seeds from the pet's posts (not the logged-in user's), so a Cat pet with 0 posts reads "害羞" / shows cat thoughts like "呼噜呼噜".
  - Tap 喂食 / 摸摸 / 玩耍 on a `PetProfileView` virtual pet → animations fire (verify they work the same as on `ProfileView`).
  - Navigate between pet profiles → `.id(pet.id)` resets the VirtualPetView state so counters/thoughts don't leak between pets.
- ✅ No database schema change
- ✅ No migration needed — `updatePetAvatar` writes to the existing `pets.avatar_url` column via Storage URL

## 2026-04-17 — Pet editor + Discover filters: restrict species to Dog and Cat (#36)

## Summary

User ask: "Only make Dog and Cat as available pet species." Rabbit / Bird / Hamster / Other were offered in the pet creation/edit form (and as filter tabs in the Discover page) but had no species-specific interactive experience beyond the static `PetCharacterView` illustrations. Narrowed the species picker to just Dog and Cat, which are the two species that get a full virtual-pet stage after #35 (`LargeDog` + breed variants for dogs, `PetCharacterView.Cat` for cats).

Legacy pets in the database with a non-Dog/Cat species still render correctly — the defensive fallbacks in `FeedView`, `PetCharacterView`, `PostDetailView`, `CreatePostView`, and `PetProfileView` are untouched. The change is purely about what the picker offers going forward.

3 files changed, ~30 lines.

## Changes

### `Views/ProfileView.swift` — `speciesOptions`
- Trimmed from `[Dog, Cat, Rabbit, Bird, Hamster, Other]` to `[Dog, Cat]`.
- Added a rationale comment tying the decision to the virtual-pet stage coverage.

### `Views/ContactsView.swift` — `DiscoverFilter`
- Removed `.rabbits` and `.birds` cases from the enum and from `matchesFilter`.
- Filter tab bar now shows `全部 / 狗狗 / 猫咪` only.

### `Views/VirtualPetView.swift` — `VirtualPetState.species` doc comment
- Updated to clarify that the editor only creates Dog/Cat post-#36, but legacy species strings still render through graceful fallbacks.

## Files Changed

| File | +/− |
|---|---|
| `PawPal/Views/ProfileView.swift` | +11 / -3 (≈) |
| `PawPal/Views/ContactsView.swift` | +6 / -15 (≈) |
| `PawPal/Views/VirtualPetView.swift` | +4 / -3 |
| `CHANGELOG.md` | this entry |
| `docs/known-issues.md` | spot-check addendum for #36 |

## Validations

- ❓ `xcodebuild` — not available in authoring sandbox; **build verification still pending**
- ⚠️ Manual spot-checks pending:
  - Tap "+" to add a new pet → species chip row shows 🐶 Dog and 🐱 Cat only, no rabbit/bird/hamster/other
  - Edit an existing pet → same (chip row is Dog + Cat)
  - Existing cat pet in the editor: "Cat" remains selected after opening the editor
  - Existing pet with a legacy species (e.g. "Rabbit"): editor shows neither chip selected visually — need to verify the pet can still be saved without picking a new species (`pet?.species ?? "Dog"` seeds the state so the first-open default is "Dog" if the original value is in the list; otherwise it stays on the original string but no chip is highlighted)
  - Discover filter tab bar shows `全部 / 狗狗 / 猫咪` only
  - Dogs and Cats filter tabs still match the right posts
  - Legacy records with rabbit/bird species still render with correct emoji in FeedView / ContactsView cards (fallback paths untouched)
- ✅ No database schema change; no migration required

## 2026-04-17 — VirtualPetView is now species-agnostic — cats get feed/pet/play too (#35)

## Summary

User feedback: "when I create a new pet, like a cat. The virtual cat does not have the same feed/pet/play". Root cause was in `ProfileView.featuredPetSection` — the layout branched on `isDog` and routed non-dogs through a legacy static `PetCharacterView` + stat-pills card with none of the interactive chrome (no feed/pet/play, no mood/hunger/energy bars, no thought bubble, no tap-to-boop).

Taught `VirtualPetView` to render any species: dogs continue to use the custom `LargeDog` canvas (with accessory chips for bow/hat/glasses); cats/rabbits/birds/hamsters/"other" now route through `PetCharacterView` *inside* the same stage, sharing all the interactive chrome. The three accessory chips in the header are hidden for non-dogs (the bow/hat/glasses are SwiftUI drawings specific to `LargeDog`). Thought-bubble copy is species-aware so a cat reads "呼噜呼噜 / 窗外有鸟!" instead of dog-specific "*摇尾巴ing*".

End state: creating a cat gives the same feed/pet/play/boop experience as a dog, with a cat-appropriate illustration and cat-flavoured thoughts.

2 files changed, ~110 lines.

## Changes

### `Views/VirtualPetView.swift`
- `VirtualPetState`: added `species: String? = nil` (defaults to Dog for backwards compat) and an `isDog` computed property that normalises the species string.
- `headerRow`: accessory chip HStack wrapped in `if state.isDog` — chips hidden for non-dogs.
- `stage`: replaced the inline `LargeDog(...)` with a `petCharacter` ViewBuilder that switches between `LargeDog` (dogs) and `PetCharacterView(species:, mood:, size: 170, onTap: { tapPet() })` (everything else). Both paths share the same scale/offset/breathing/jump modifiers so the feel is identical.
- New `petCharacterMood` computed property maps the numeric state (mood/hunger/energy) into a `PetCharacterMood` case so the non-dog character's expression tracks the stats (energy < 30 → sleeping, mood ≥ 85 → excited, energy ≥ 75 → energetic, mood < 40 → chill, else happy).
- `thoughts(for:species:)`: species-aware pool. Cat / Rabbit / Bird / Hamster / Other get their own copy; dogs retain the existing breed-variant branch. `species:` defaults to nil so the single-arg form still compiles.
- Thought rotation task updated to pass `state.species` to the new `thoughts(for:species:)` signature.
- Added a third preview card featuring a cat ("Mochi / 橘猫") so the non-dog path is covered.

### `Views/ProfileView.swift`
- `featuredPetSection`: removed the `isDog` branch and the legacy `PetCharacterView`-plus-stat-pills VStack. All species now route through a single `VirtualPetView(state:)` invocation that passes `species: pet.species` into the state.
- `initialThought(for:stats:)` now calls `VirtualPetView.thoughts(for:species:)` with the pet's species so the first-seen thought matches the species.

## Files Changed

| File | +/− |
|---|---|
| `PawPal/Views/VirtualPetView.swift` | +80 / -14 (≈) |
| `PawPal/Views/ProfileView.swift` | +8 / -60 (≈) |
| `CHANGELOG.md` | this entry |
| `docs/known-issues.md` | spot-check addendum for #35 |

## Validations

- ❓ `xcodebuild` — not available in authoring sandbox; **build verification still pending**
- ⚠️ Manual spot-checks pending:
  - Create a new pet with species "Cat" → profile shows the VirtualPetView stage with header (虚拟{name}), mood/hunger/energy bars, feed/pet/play buttons, thought bubble, tap-to-boop. Accessory chip row is hidden (no 🎀/🎩/👓 for cats).
  - Tap 喂食 on a cat → hunger bar animates up, thought changes to "真香~", 🍖 emoji floats up from the cat.
  - Tap 摸摸 on a cat → mood bar animates up, thought changes to "是个乖宝宝", ✨ emoji floats up.
  - Tap 玩耍 on a cat → energy down, mood up, jump animation, thought "一起玩!", 🎾 emoji floats up.
  - Tap the cat itself → heart pops up, cat springs slightly, "已经摸了 {name} N 下" counter increments.
  - Thought rotation every 4.5s picks cat-flavoured copy (e.g. "呼噜呼噜", "窗外有鸟!") — not dog thoughts.
  - Rabbit / Bird / Hamster / Other species also render correctly with their own thought pools.
  - Existing Dog flow is unchanged (bow/hat/glasses still appear in the header, LargeDog renders).
  - Switching between a dog pet and a cat pet resets state cleanly (`.id(pet.id)` on the VirtualPetView).
- ✅ No database or service changes — pure view-layer refactor
- ✅ Backwards compat: `VirtualPetState(species: nil, ...)` and `VirtualPetView.thoughts(for: .golden)` both still compile

## 2026-04-17 — ProfileView: fix photo bleed + tighten text-tile typography (#34)

## Summary

User screenshot after #33 showed two remaining issues in the profile post grid:

1. **The middle image tile (flowers) was bleeding pink into the adjacent "Image test" tile.** The outer ZStack used `.aspectRatio(1, contentMode: .fill)` — with `.fill` the modifier proposes a larger size than the grid cell when the intrinsic content is bigger, so the photo spilled past the cell boundary before `.clipped()` on the ZStack could catch it.
2. **Text-only tiles used a `cardSoft → cardSoft.opacity(0.7)` gradient** that went translucent at the bottom-right. Any warmth in the backdrop leaked through and made tiles read as subtly dirty.
3. **The "如果我发一条纯文字，特别长的动态怎么办呢" tile wrapped to 4 tight lines** with the last line orphaned as "么办呢". 12pt semibold was a hair too wide for the square — slimming to 11.5pt fits one more CJK glyph per line.

Fixed by switching the tile to the `Color.clear.aspectRatio(1, .fit).overlay { … }.clipped()` idiom (rock-solid 1:1 container that never overflows), adding explicit `.frame(maxWidth:.infinity, maxHeight:.infinity).clipped()` on the photo itself, replacing the gradient fill with a flat `cardSoft`, and dropping caption type from 12pt → 11.5pt with `lineLimit(5 → 6)`.

1 file changed, ~30 lines.

## Changes

### `Views/ProfileView.swift` — `profilePostTile(_:)`
- Structure: wrapped the whole tile in `Color.clear.aspectRatio(1, contentMode: .fit).overlay { ZStack … }.clipped()`. Outer ZStack no longer carries aspect-ratio or clip modifiers.
- Image path: `.scaledToFill().frame(maxWidth: .infinity, maxHeight: .infinity).clipped()` — photo is now explicitly framed + clipped inside the 1:1 container, so nothing can bleed into a neighbouring cell.
- Comment added explaining why the previous `.aspectRatio(1, .fill)` approach was fragile (so a future refactor doesn't revert it).

### `Views/ProfileView.swift` — `textOnlyProfileTile(caption:)`
- Fill: `LinearGradient(cardSoft → cardSoft.opacity(0.7))` → flat `Rectangle().fill(PawPalTheme.cardSoft)`.
- Caption font: `12pt semibold` → `11.5pt semibold` (fits one more CJK glyph per line).
- Clamp: `lineLimit(5)` → `lineLimit(6)`.
- Comment in-line with the rationale for the size pick.

## Files Changed

| File | +/− |
|---|---|
| `PawPal/Views/ProfileView.swift` | ~30 |
| `CHANGELOG.md` | this entry |
| `docs/known-issues.md` | spot-check addendum for #34 |

## Validations

- ❓ `xcodebuild` — not available in authoring sandbox; **build verification still pending**
- ⚠️ Manual spot-checks pending:
  - Image tile: photo fills the 1:1 cell, no pink/magenta bleed into neighbouring tiles (before + after screenshots)
  - Text-only tile: solid cream fill (no diagonal fade), reads as flat and clean
  - Long caption ("如果我发一条纯文字，特别长的动态怎么办呢") wraps comfortably, no orphaned 4th line
  - Grid is still 3-column, tiles are still square, all badges legible
  - Tap targets still navigate to PostDetailView
- ✅ No data-flow or behavioural changes; layout + typography only

## 2026-04-17 — ProfileView: clean up text-only post tiles in the grid (#33)

## Summary

User screenshot of the profile Posts tab flagged three issues in `profilePostTile`:

1. **Every text-only tile showed a `text.alignleft` SF Symbol** (three horizontal lines) behind the caption — the symbol was intended as a placeholder icon but it sat under the caption text and read as broken/loading UI instead of a deliberate design element.
2. **Like-count badge was invisible on text tiles** — `.foregroundStyle(.white)` was calibrated for overlaying photos. Over `cardSoft` fill it vanished. The `♡ 0` / `♡ 1` on "Hello World" and "Hi" were barely legible in the screenshot.
3. **Long captions clipped at the right edge** — the caption overlay had 8pt padding but no width constraint, so it ran under the badge area. "如果我发一条纯文字，特别长的动态怎么办呢" was chopped before "呢".

Replaced the placeholder-with-icon pattern with a dedicated `textOnlyProfileTile` body: soft diagonal gradient fill, accent-tinted `quote.opening` glyph above the caption, caption rendered at 12pt semibold (was 11pt) as the tile's hero content. Clipped to 5 lines with reserved bottom padding (28pt) so the last line never collides with the badge. Badge moved into a translucent black pill that stays readable on both image and text backgrounds (opacity 0.38 over photos, 0.55 over cream).

1 file changed, ~50 lines.

## Changes

### `Views/ProfileView.swift` — `profilePostTile(_:)`
- Removed `profileTilePlaceholder(icon: "text.alignleft")` for text-only posts; introduced `textOnlyProfileTile(caption:)` sibling helper.
- Like-count badge: `.shadow(black 0.45)` → translucent black `Capsule` background (`0.38` over images, `0.55` over text tiles) so the count is always readable.
- Added `hasImage` hoisted flag so the badge picks the right opacity.

### `Views/ProfileView.swift` — new `textOnlyProfileTile(caption:)`
- Diagonal `cardSoft → cardSoft.opacity(0.7)` gradient fill for a subtle depth cue (was flat cardSoft).
- Accent-tinted `quote.opening` at 12pt above the caption.
- Caption: 12pt semibold primaryText, 5-line clamp with `.tail` truncation, `maxWidth: .infinity` so it wraps inside the tile box.
- Padding: 11pt horizontal / 11pt top / 28pt bottom — the bottom reserve keeps the caption out of the badge's corner.

## Files Changed

| File | +/− |
|---|---|
| `PawPal/Views/ProfileView.swift` | +52 / -19 (≈) |
| `CHANGELOG.md` | this entry |
| `docs/known-issues.md` | spot-check addendum for #33 |

## Validations

- ❓ `xcodebuild` — not available in authoring sandbox; **build verification still pending**
- ⚠️ Manual spot-checks pending:
  - Text-only post "Hello World" / "Hi": no three-line glyph, only a small orange quote icon + the caption text; like count in a dark pill at the bottom-left reads clearly
  - Text-only post "如果我发一条纯文字，特别长的动态怎么办呢": caption wraps within the tile, doesn't clip on the right, truncates with ellipsis if it exceeds 5 lines
  - Image post (flowers): image fills the tile as before; like-count pill sits in bottom-left with a slightly lighter black pill (0.38 opacity) so it's still readable without overpowering the photo
  - Grid layout: tiles remain square, still 3-column
  - Tapping a text-only tile still navigates to `PostDetailView`
- ✅ No data-flow changes; presentation only

## 2026-04-17 — VirtualPetView: give stage headroom so thought bubble sits above the pet (#32)

## Summary

User feedback on #31: "聊天框位置不对，很奇怪" (the chat bubble position is wrong, very strange). Top-leading placement avoided accessory collision but moved the bubble's tail (which anchors at the bottom-LEFT of the bubble via `offset(x:22, y:5)`) to point at empty floor — the bubble read as disconnected from the pet rather than as a thought emanating from it.

Fixed by giving the stage vertical headroom instead of pushing the bubble sideways: stage height 190 → 220. The extra 30pt sits above the (still bottom-aligned) dog, and the bubble moves back to top-trailing so its tail points down-and-inward toward the dog's head — the natural cartoon-thought silhouette. With the hat accessory at stage-y≈53 and the bubble bottom at stage-y≈46, there's ~7pt of air between them, so no occlusion in either direction.

1 file changed, ~15 lines.

## Changes

### `Views/VirtualPetView.swift` — `stage` computed property
- Stage frame: `190` → `220` (both outer ZStack and inner pet VStack)
- Thought bubble: `.padding(.leading, 20)` → `.padding(.trailing, 24)`; alignment `.leading` → `.trailing`
- Bubble top padding tightened: `14` → `10` (uses the new headroom, sits close to the top of the stage)
- Expanded geometry comment: derived the 7pt clearance from accessory tops so the next person can reason about it instead of eyeballing

## Files Changed

| File | +/− |
|---|---|
| `PawPal/Views/VirtualPetView.swift` | ~15 |
| `CHANGELOG.md` | this entry |
| `docs/known-issues.md` | spot-check addendum for #32 |

## Validations

- ❓ `xcodebuild` — not available in authoring sandbox; **build verification still pending**
- ⚠️ Manual spot-checks pending:
  - Trigger a thought with **no accessory** — bubble sits above-right of the dog's head, tail pointer visibly aims at the head, reads as "thought balloon from the pet"
  - Equip 🎀 (bow) + thought — bow stays on right ear tip, bubble floats in the new headroom above, both are fully visible
  - Equip 🎩 (top hat) + thought — hat stays on crown, bubble is above with clearance, no occlusion
  - Stage now reads as taller (30pt more) but still proportional — confirm the card height isn't awkward; statsRow and action tiles below are unchanged
  - Tail wag animation at bottom of stage is unchanged — the extra height is all at the top
- ✅ No behaviour changes; purely layout

## 2026-04-17 — VirtualPetView: relocate thought bubble + reseat bow (#31)

## Summary

#30 flipped the z-order so the bubble text was always on top — but that just inverted the problem: now the bubble covered whichever accessory was on screen (user screenshot: pink bow partially hidden behind "*摇尾巴ing*"). Z-order alone can't win both directions; the bubble and top-right accessories (bow, hat brim) occupy the same rectangle. Fixed spatially: moved the thought bubble to the **top-leading** corner of the stage so it never overlaps an accessory, and reseated the bow at (130, 32) so it sits on the right ear tip instead of floating slightly off it.

1 file changed, ~10 lines.

## Changes

### `Views/VirtualPetView.swift` — `stage` thought bubble anchor
- `.padding(.trailing, 20)` → `.padding(.leading, 20)`
- `.frame(maxWidth: .infinity, alignment: .trailing)` → `.frame(maxWidth: .infinity, alignment: .leading)`
- Expanded comment explaining the spatial reasoning (hat at x:90 center, bow at x:135 right ear, so leading-anchored bubble is the only safe spot).

### `Views/VirtualPetView.swift` — `DogAvatar.accessoryView .bow`
- Size: 34pt → 32pt (slightly slimmer so the knot doesn't dominate the small ear).
- Position: `(x: 135, y: 25)` → `(x: 130, y: 32)`. Right ear is a rotated ellipse centered at (126, 52), rx:15 ry:24, rotation +20°, with tip near (134, 30); the new anchor sits the bow on the ear rather than floating above-and-outside it.
- Added explanatory comment with the geometry so future adjustments don't regress.

## Files Changed

| File | +/− |
|---|---|
| `PawPal/Views/VirtualPetView.swift` | ~10 |
| `CHANGELOG.md` | this entry |
| `docs/known-issues.md` | spot-check addendum for #31 |

## Validations

- ❓ `xcodebuild` — not available in authoring sandbox; **build verification still pending**
- ⚠️ Manual spot-checks pending:
  - Equip 🎀 (bow) + trigger a thought — bubble sits top-left, bow sits on top of the right ear tip, neither element obscures the other
  - Equip 🎩 (top hat) + trigger a thought — bubble still top-left, hat still centered on the head crown, no collision
  - No accessory + trigger a thought — bubble renders in the top-leading corner (previously top-trailing). Tail is at the bottom-left of the dog frame so it does NOT collide with the bubble column
  - Bubble entrance/exit animation still reads as a soft drop-in from the top (transition unchanged)
- ✅ No behaviour changes; purely layout/positioning

## 2026-04-17 — VirtualPetView: thought bubble now draws above accessories (#30)

## Summary

Even after #29 scaled and reseated the top hat, the hat still visually hid the 思考泡泡 text when both were on screen. Root cause was z-order, not geometry: inside the `stage` ZStack the thought bubble was declared *before* the pet+accessory VStack, so the dog (and any accessory it's wearing) rendered on top of the bubble. Reordered the ZStack so the thought bubble is declared last.

Purely structural — no geometry, typography, or colour changes.

1 file changed, ~12 lines reordered.

## Changes

### `Views/VirtualPetView.swift` — `stage` computed property
- Moved the `if !state.thought.isEmpty { thoughtBubble … }` block from its previous position (between the floor-line VStack and the pet VStack) to the end of the ZStack, so it renders last and always sits above the dog + accessory.
- Added a comment anchoring the placement so the next refactor doesn't re-sort it: "Declared LAST so it draws above the pet + any accessory (top hat, bow, glasses)."

## Files Changed

| File | +/− |
|---|---|
| `PawPal/Views/VirtualPetView.swift` | 12 lines reordered, 4 lines of comment added |
| `CHANGELOG.md` | this entry |
| `docs/known-issues.md` | spot-check addendum for #30 |

## Validations

- ❓ `xcodebuild` — not available in authoring sandbox; **build verification still pending**
- ⚠️ Manual spot-checks pending:
  - Tap 🎩 so the dog wears the hat, then trigger a thought (tap the dog or `play()` to fire "一起玩!") — the bubble text is fully visible; the hat crown never overlaps the typography
  - With no accessory, bubble still appears in the top-right with the same padding
  - Reaction emoji (`reactEmoji`, e.g. ❤️) still floats above the dog's head and is unaffected by the reorder
- ✅ No behaviour changes; purely view-hierarchy ordering

## 2026-04-17 — VirtualPetView: fix oversized floating top-hat accessory (#29)

## Summary

User screenshot: top-hat accessory floated far above Kaka's head, dwarfed the dog, and overlapped the thought bubble ("喜欢你" partially occluded). The hat was sized at 58pt and positioned at y:0 of the 180×170 dog frame — center of the emoji was at the very top of the frame, so most of the hat drew above it. Calibrated the hat to the same scale as the bow (38pt centered over the head crown).

1 file changed, 3 lines of code + comment.

## Changes

### `Views/VirtualPetView.swift` — `DogAvatar.accessoryView .hat` case
- Font size: `58pt` → `38pt` (matches the bow at 34pt; slightly larger so it reads as a full top-hat silhouette).
- Position: `(x: 90, y: 0)` → `(x: 90, y: 22)`. The head ellipse is drawn within `sy(26)...sy(114)`, so y ≈ 22 places the hat brim right on the forehead. Added a comment explaining the math so the next person isn't guessing.
- Bow and glasses cases unchanged.

## Files Changed

| File | +/− |
|---|---|
| `PawPal/Views/VirtualPetView.swift` | 3 lines of code + explanatory comment |
| `CHANGELOG.md` | this entry |

## Validations

- ❓ `xcodebuild` — not available in authoring sandbox; **build verification still pending**
- ⚠️ Manual spot-checks pending:
  - Tap the 🎩 accessory chip → hat sits on the dog's head (brim on forehead, crown above the ears), no longer floats in the thought-bubble zone
  - Thought bubble text is no longer occluded by the hat
  - Hat reads proportional to the dog body — similar visual weight to the bow
  - Bow (🎀) placement unchanged (near right ear)
  - Glasses placement unchanged
- ✅ No behaviour changes; purely positioning/sizing

---

## 2026-04-17 — Feed: text-only caption un-bolded (#28)

## Summary

User feedback: "字体不要加粗" on the text-only post caption. The previous pass (#22) landed on SF Pro 15pt medium for a "hint of extra weight" — the user read that as bold. Dropped to regular weight.

1 file changed, 1 line of code + doc comment.

## Changes

### `Views/FeedView.swift` — `textOnlyCaption`
- Font weight: `.medium` → `.regular` at the same 15pt size. Body reads as calm prose now, not emphasised.
- Doc comment updated to reflect the new weight and reference the feedback.

Image-post caption (`captionText`) is untouched — it continues to inline-bold the handle the way Instagram-style captions do.

## Files Changed

| File | +/− |
|---|---|
| `PawPal/Views/FeedView.swift` | 1 line of code + comment retune |
| `CHANGELOG.md` | this entry |

## Validations

- ❓ `xcodebuild` — not available in authoring sandbox; **build verification still pending**
- ⚠️ Manual spot-checks pending:
  - Text-only post: caption body renders in regular (non-bold) SF Pro at 15pt
  - Image post caption: handle is still bold inline; caption body unchanged
- ✅ No behaviour changes

---

## 2026-04-17 — VirtualPetView: replace "球球" copy (#27)

## Summary

User requested that "球球" (ball-ball) be swapped for something else. Two occurrences in `VirtualPetView.swift`: the `play()` action's thought bubble and the golden-retriever thought pool. Replaced both with less ball-specific phrasing.

1 file changed, 2 lines.

## Changes

### `Views/VirtualPetView.swift`
- `play()` thought: `"球球!"` → `"一起玩!"` — reads as generic "let's play!" so it works for breeds that aren't ball-obsessed.
- Golden thought pool: `"要玩球球吗?"` → `"出去玩吗?"` — still on-brand for goldens (famously up for anything), no longer ball-specific.

## Files Changed

| File | +/− |
|---|---|
| `PawPal/Views/VirtualPetView.swift` | 2 lines |
| `CHANGELOG.md` | this entry |

## Validations

- ❓ `xcodebuild` — not available in authoring sandbox; **build verification still pending**
- ⚠️ Manual spot-checks pending:
  - Tap "玩耍" on the virtual pet — thought bubble reads "一起玩!"
  - Let the thought rotation tick through the golden pool — "出去玩吗?" appears in place of the old ball line
- ✅ No behaviour or layout changes; purely copy

---

## 2026-04-17 — VirtualPetView: breathing room + age-unit doubling fix (#26)

## Summary

User feedback (screenshot): "This is a little 拥挤?" on the virtual pet card. Two problems visible:
1. Typography bug: the breed/age line read "Border Collie · 5 years 岁" because the stored `age_text` used an English unit our formatter didn't recognise, so we appended 岁 on top.
2. Layout: three rows (header / stats / actions) pressed tight at 14pt spacing on 18pt padding; each section felt like it was leaning on the next.

Fixed the age formatter to understand English units and retuned the spacing so the card reads as three distinct chunks. Also grouped stage + stats into one inner block to signal that the bars describe the character above them.

2 files changed, ~35 lines net.

## Changes

### `Views/ProfileView.swift` — `formattedAge(for:)`

Extended the unit-detection logic to recognise common English tokens and rewrite them to Chinese:

| English | → Chinese |
|---|---|
| `year`, `years`, `yr`, `yrs` | 岁 |
| `month`, `months`, `mos` | 个月 |
| `week`, `weeks` | 周 |
| `day`, `days` | 天 |

Now "5 years" renders as "5 岁" rather than "5 years 岁". Ordered longest-match-first (`years` before `year`) to avoid partial-substring doubling. Also added 天 to the Chinese-unit check so "3 天" isn't double-suffixed.

### `Views/VirtualPetView.swift` — layout

- **Outer VStack spacing**: `14pt` → `20pt` (groups card into three visual chunks)
- **Outer padding**: `18pt` → `20pt`
- **Stage + stats** now wrapped in a shared `VStack(spacing: 14)` so they read as one block (bars explain the character above them)
- **Header row**: title VStack spacing `2pt` → `3pt`; added `spacing: 12` between title and accessory chips; `Spacer(minLength: 12)` prevents crowding on narrow widths; title line now truncates to one line tail
- **Accessory chips gap**: `6pt` → `8pt`
- **Stats row gap**: `12pt` → `16pt` (bars read as distinct gauges, not a packed strip)
- **Actions row gap**: `8pt` → `10pt`
- **Action button vertical padding**: `11pt` → `14pt`; inner VStack spacing `4pt` → `6pt` (tile reads as a proper tap target)
- **Tap-count caption** gains `.padding(.top, 2)` so it separates from the actions row

No behaviour changes — feed/pat/play animations and thought rotation untouched.

## Files Changed

| File | +/− |
|---|---|
| `PawPal/Views/ProfileView.swift` | ~+25 / -3 lines (age formatter extension) |
| `PawPal/Views/VirtualPetView.swift` | ~+20 / -10 lines (spacing retune + grouped stage+stats) |
| `CHANGELOG.md` | this entry |
| `docs/known-issues.md` | spot-check added |

## Validations

- ❓ `xcodebuild` — not available in authoring sandbox; **build verification still pending**
- ⚠️ Manual spot-checks pending:
  - Pet with `age_text = "5 years"` renders as "5 岁" in the VirtualPet header and the pet editor preview
  - Pet with `age_text = "3 months"` renders as "3 个月"; `age_text = "2 岁"` unchanged
  - Virtual pet card header: title and the three accessory chips each have visible gaps between them; no overlap on iPhone SE-width screens
  - Stage + stats read as one block with a calm 14pt gap; actions below sit 20pt away
  - Action tiles feel like real buttons (14pt vertical padding, 10pt between tiles)
  - Bars "心情 / 饱食 / 活力" have a clear gap between them (16pt, not 12pt)
  - "已经摸了 Kaka N 下 🐾" footer separates from the actions row
- ✅ `xcodebuild test` — not run
- ✅ Do-not-break flows — no behaviour changes to tap/feed/play/accessory actions

---

## 2026-04-17 — Profile: denser header and highlights strip (#25)

## Summary

User feedback (with screenshot): "move on to the profile view, this seems too empty." The upper section of the profile — compact user row, stats, single-pet `我的宠物` band — had a lot of whitespace and very little signal when the user had few posts or pets. Added four small things that together fill the gap with real info, not chrome: a bio / prompt row in the header, a ghost "+" bubble as a peer to real pets, a primary `编辑资料` pill + share button, and a three-card highlights strip between the pets band and the featured pet. Also swapped the hard dividers for a softer hairline to make the flow read as one column.

1 file changed, ~210 lines net.

## Changes

### `Views/ProfileView.swift`

**Header (`profileHeader`)**

- **New `bioLine` row** between the handle row and stats. If `profile.bio` is set, renders it inside a cream card with a quote glyph and a `pencil` edit affordance; tap opens the account editor. If bio is empty, renders an accent-tinted prompt card — "给主页加一段介绍吧" + sub-copy + chevron — to nudge the user without looking like an empty state. Replaces the implicit empty band that appeared between `@cs3736 · 宠物家长` and the stats row.
- **New `headerActionRow`** under the stats: primary `编辑资料` capsule with an accent gradient + soft shadow (goes straight to the edit sheet) and a trailing 40pt circular `ShareLink` with `square.and.arrow.up`. The share URL is a placeholder `pawpal://u/<handle>` that iOS will surface as plain text until we stand up universal links — share sheet works today, deep-linking can come later without changing the call site.
- Tightened VStack spacing 16 → 14 so the header reads denser.

**Pets band (`petsBand`)**

- **New `addPetGhostBubble`** appended to the end of the pet scroll row. Peer-sized at 72pt with a dashed accent ring + "+" glyph and "添加宠物" label. Tapping opens the same `showingAddPet` sheet as the header "+ 添加" button. Fills the visual gap when the user has only one or two pets — the band no longer terminates with a lonely avatar and lots of empty trailing space.

**New `highlightsStrip`** (inserted between `petsBand` and `featuredPetSection`)

Three compact cards. All values derive from data already loaded; no new backend:

1. `💛 累计点赞` — sum of `likeCount` across `postsService.userPosts`.
2. `📝 最新动态` — relative time of the most recent post (`刚刚 / N分钟前 / N小时前 / 昨天 / N天前 / N个月前 / N年前`); falls back to `尚未发布` when the user has no posts.
3. `🐾 陪伴天数` — days since the earliest pet's `created_at`. Caps at `一年以上` past 365 days.

Each card has a warm rounded-rect (16pt radius) with a hairline border; tints differ (red-tint, accent-tint, subtle) so the row reads as scanny icons, not a wall of the same color.

**Dividers**

- Replaced three `Divider()` calls in the body with a new `softDivider` computed property — a 0.5pt hairline rectangle with 20pt horizontal padding. The default `Divider()` full-bleed separator read harsh against the warm design; the new treatment keeps section boundaries legible without chopping the page into slabs.

### Derived properties added
- `totalLikesAcrossPosts: Int`
- `latestPostRelative: String`
- `companionshipDurationText: String`
- `shareURLForSelf: URL`, `shareMessage: String`

## Files Changed

| File | +/− |
|---|---|
| `PawPal/Views/ProfileView.swift` | ~+220 / -10 lines (bio row, action pill, ghost bubble, highlights strip, soft divider) |
| `CHANGELOG.md` | this entry |
| `docs/known-issues.md` | spot-check list added for the redesign |

## Validations

- ❓ `xcodebuild` — not available in authoring sandbox; **build verification still pending**
- ⚠️ Manual spot-checks pending:
  - Header: bio card renders between `@handle · 宠物家长` row and the stats. Empty state shows the sparkle prompt; tapping either state opens the edit sheet
  - After the stats: the `编辑资料` gradient pill + circular share button row renders. Share button opens the system share sheet
  - Pets band: last item in the scroll row is a dashed-ring ghost bubble labeled "添加宠物". Tapping opens the add-pet sheet
  - Highlights strip: three cards sit between the pets band and the featured pet. Values populate correctly (likes, "3小时前", "5天")
  - Section separators are now a hairline with 20pt side padding, not a full-bleed `Divider()`
  - Empty state (no posts / no pets) still renders without crashing — `最新动态` shows `尚未发布`, `陪伴天数` shows `—`
- ✅ `xcodebuild test` — not run
- ✅ Do-not-break flows — Auth, Feed, Create post paths untouched; Profile backend calls (`loadAll`) unchanged

---

## 2026-04-17 — Feed: text-only caption aligns with profile image (#24)

## Summary

User clarified the alignment intent after #23: "let the text start align with the profile image." The 56pt handle-column indent read too indented — the user wanted the caption to start at the same x-coordinate as the avatar (the card's inner 14pt edge), not under the display name. Reverted the leading indent.

1 file changed, ~3 lines net.

## Changes

### `Views/FeedView.swift` — `PostCard.body` text-only branch
- **Leading padding**: `56pt` → `14pt`. Text now starts flush with the avatar's left edge, not the handle text.
- Collapsed `.padding(.leading, 56) + .padding(.trailing, 14)` back to `.padding(.horizontal, 14)`.
- Updated the comment to explain the new alignment target (profile image, not handle).

## Files Changed

| File | +/− |
|---|---|
| `PawPal/Views/FeedView.swift` | ~+5 / -6 lines (indent revert + comment rewrite) |
| `CHANGELOG.md` | this entry |
| `docs/known-issues.md` | spot-check updated |

## Validations

- ❓ `xcodebuild` — not available in authoring sandbox; **build verification still pending**
- ⚠️ Manual spot-checks pending:
  - Text-only post: caption's leading edge aligns with the avatar above it (a vertical ruler through the avatar's left edge passes through the first character of the caption)
  - Caption does **not** align with the handle text — the handle sits further right because of the 32+10pt offset
  - Image-post caption unchanged — still at the 14pt inner edge
- ✅ `xcodebuild test` — not run

---

## 2026-04-17 — Feed: text-only caption aligns with handle column (#23)

## Summary

User feedback: "The alignment. The padding at the start." On text-only posts the caption was flush to the card's 14pt inner edge while the header handle/time sat 56pt in (after the 32pt avatar and 10pt HStack gap). That misalignment made header and body read as two disconnected columns. Indented the caption to match the handle column so the post reads as a single aligned stack — a Twitter/Threads-style treatment rather than Instagram's full-bleed caption.

1 file changed, ~3 lines net.

## Changes

### `Views/FeedView.swift` — `PostCard.body` text-only branch
- **Leading padding**: `14pt` → `56pt` (card padding 14 + avatar 32 + HStack gap 10). The caption now starts directly under the display name / handle, not under the avatar.
- **Trailing padding**: kept at `14pt` (matches the card's inner edge on the right — no reason to indent on the trailing side).
- Replaced `.padding(.horizontal, 14)` with explicit `.padding(.leading, 56) + .padding(.trailing, 14)` for clarity.
- Added a comment explaining the 56pt number so the next person doesn't treat it as a magic value.

Image-post caption (under the reaction row) is unchanged — it still uses symmetric 14pt horizontal padding because it's visually anchored to the image edge above it, not the handle.

## Files Changed

| File | +/− |
|---|---|
| `PawPal/Views/FeedView.swift` | ~+5 / -1 lines (indent + comment) |
| `CHANGELOG.md` | this entry |
| `docs/known-issues.md` | spot-check added |

## Validations

- ❓ `xcodebuild` — not available in authoring sandbox; **build verification still pending**
- ⚠️ Manual spot-checks pending:
  - Text-only post: caption's leading edge aligns with the handle text above it (not with the avatar, not with the card edge)
  - Image-post caption unchanged — still starts at the 14pt inner edge
  - Long caption wrapping: second/third lines also start at the 56pt indent (not flush-left wrap)
- ✅ `xcodebuild test` — not run

---

## 2026-04-17 — Feed: text-only caption — back to default SF Pro at 15pt medium (#22)

## Summary

User feedback on the previous pass: "font size is too big, also the font style still looks weird." The `.rounded` design read cartoony for prose and 18pt felt shouty. Pulled back to default SF Pro at a normal reading size.

1 file changed, ~15 lines net.

## Changes

### `Views/FeedView.swift` — `textOnlyCaption`
- **Font**: `.system(size: 18, weight: .regular, design: .rounded)` → `.system(size: 15, weight: .medium)`. Default SF Pro at the same reading size the rest of iOS uses for body prose. Medium weight gives the text a little character without being shouty.
- **Tracking**: removed the -0.1pt display tracking (not needed at 15pt).
- **Line spacing**: 7 → 4pt. Normal reading cadence.
- **Expand label**: "展开阅读" (rounded semibold) → "展开" (default semibold). Shorter and stylistically consistent.
- **Expand threshold**: 220 → 240 chars.

### Container padding (`PostCard.body`, text-only branch)
- **Top**: 14 → 4pt (the post header's own bottom padding already gives 10pt; adding 14 more made a chasm).
- **Horizontal**: 18 → 14pt (matches image-post caption padding; 18pt felt over-padded at 15pt type).
- **Bottom**: 20 → 14pt.

## Files Changed

| File | +/− |
|---|---|
| `PawPal/Views/FeedView.swift` | ~+10 / -12 lines (font rollback, spacing retune) |
| `CHANGELOG.md` | this entry |

## Validations

- ❓ `xcodebuild` — not available in authoring sandbox; **build verification still pending**
- ⚠️ Manual spot-checks pending:
  - Text-only caption reads at a calm body-text size (not too big, not too small)
  - Font is default SF Pro — no rounded or serif design
  - Spacing feels balanced: not cramped, not cavernous
  - "展开" appears for long captions in accent color
- ✅ `xcodebuild test` — not run

---

## 2026-04-17 — Feed: text-only caption polish — rounded type, generous spacing, accent-colored expand (#21)

## Summary

User feedback on the first text-only layout: "拥挤 (crowded), font is ugly". The default SF Pro at 17pt + 2pt top padding made it read like an alert dialog. Reworked the treatment for a confident editorial feel.

1 file changed, ~20 lines net.

## Changes

### `Views/FeedView.swift` — `textOnlyCaption` + its container padding
- **Typeface**: `.system(size: 17, weight: .regular)` → `.system(size: 18, weight: .regular, design: .rounded)`. SF Rounded replaces generic SF Pro — warmer and on-brand for a pet app.
- **Tracking**: added `-0.1pt` for a slightly more polished feel at display size.
- **Line spacing**: 5 → 7pt. Meaningful breathing room between lines.
- **Clamp**: 6 → 8 lines before truncating.
- **Expand label**: "更多" (14pt secondary) → "展开阅读" (13pt semibold, `.rounded` design, accent color `#FF7A52`). More intentional and visually distinct.
- **Expand threshold**: 180 → 220 chars.
- **`.fixedSize(horizontal: false, vertical: true)`**: guards against layout edge cases where Text could collapse vertically inside the card.

### Spacing around the caption (in `PostCard.body`, text-only branch)
- **Horizontal padding**: 14 → 18pt (prose feels less squished against the card's inner edge).
- **Top padding (after header)**: 2 → 14pt (was way too tight — now has real breathing room from the handle/time line).
- **Bottom padding (before actions)**: 14 → 20pt (calmer separation before the pill row).

## Files Changed

| File | +/− |
|---|---|
| `PawPal/Views/FeedView.swift` | ~+15 / -10 lines (rounded type, tracking, spacing adjustments) |
| `CHANGELOG.md` | this entry |

## Validations

- ❓ `xcodebuild` — not available in authoring sandbox; **build verification still pending**
- ⚠️ Manual spot-checks pending:
  - Text-only caption renders in SF Rounded at 18pt — noticeably warmer and rounder than the previous default font
  - Real breathing room between the header and the text (no more cramped feel)
  - Line-spacing is comfortable to read (not squished)
  - "展开阅读" appears in PawPal accent orange for long captions; tap expands to full text
  - Image post caption is unchanged (still 14pt default)
- ✅ `xcodebuild test` — not run

---

## 2026-04-17 — Feed: text-only post layout — caption promoted above the action row (#20)

## Summary

Text-only posts previously inherited the image-post rhythm (header → pills → caption), so the caption ended up dangling below the action icons with an awkward empty gap where the photo would have been. Reworked PostCard to branch on whether the post has images:

- **Image posts**: unchanged — header → image → actions → caption → comments
- **Text-only posts**: header → caption (promoted, 17pt) → actions → comments

1 file changed, ~40 lines net.

## Changes

### `Views/FeedView.swift` — `PostCard.body`
- Wrapped the inner sequence in `if !post.imageURLs.isEmpty { ... } else { ... }`. Image branch keeps the current order; text-only branch renders `textOnlyCaption` right under the header, then the reaction row below.
- New `textOnlyCaption` view: 17pt regular type (vs. 14pt in the image variant), 5pt line spacing, 6-line clamp (vs. 2), and no inline-bold handle prefix since the text *is* the content. Dropped the tight spacing in favor of a calmer, editorial rhythm. "更多" expand threshold raised from 70 → 180 chars.
- Padding tuned so the text-only card still has a confident frame: 2pt top gap after header, 14pt bottom gap before the action pills.

## Files Changed

| File | +/− |
|---|---|
| `PawPal/Views/FeedView.swift` | ~+40 / -10 lines (PostCard body branching + new textOnlyCaption view) |
| `CHANGELOG.md` | this entry |
| `docs/known-issues.md` | spot-check for text-only variant |

## Validations

- ❓ `xcodebuild` — not available in authoring sandbox; **build verification still pending**
- ⚠️ Manual spot-checks pending:
  - Text-only post: caption renders directly below the header in 17pt; reaction pills sit below the text
  - Text-only post: no large empty space between header and icons
  - Image post: unchanged — photo still between header and pills, caption still under pills
  - "更多" still works on very long captions in both variants
- ✅ `xcodebuild test` — not run

---

## 2026-04-17 — Feed redesign: break from Instagram template — cream page, floating cards, pill actions, stories eyebrow (#19)

## Summary

User felt the feed was "exactly the same as Instagram" and asked for something still functional but visually differentiated. Pulled three defining Instagram moves: the flat white edge-to-edge canvas, the four-spaced-glyphs action row, and the standalone "X 次点赞" caption-preamble. Replaced them with a PawPal-native vocabulary: warm cream page, floating white cards with inset rounded photos, warm-cream pill buttons that bake the count into the icon, a pill-style follow button, and a "小伙伴动态" eyebrow on the stories card.

1 file changed, ~190 lines net (mostly PostCard body + reactionRow rewrite + page container).

## Changes

### Page container (`Views/FeedView.swift`)
- **Background**: `Color.white` → `PawPalTheme.background` (cream `#FAF6F0`). Single biggest visual shift; immediately reads as a warm journal rather than an IG feed.
- **Stories rail**: wrapped in a floating white card (22pt radius, `softShadow`, 14pt horizontal inset) with a new "🐾 小伙伴动态" eyebrow above it. No more inline-on-white IG rail.
- **Post rhythm**: each post now a floating white card with 22pt corner radius, `softShadow`, 14pt horizontal inset, 18pt gap between cards.

### PostCard (`Views/FeedView.swift` — `body`, `imageSection`, `reactionRow`)
- **Card**: `.background(Color.white).clipShape(RoundedRectangle(22)).shadow(softShadow, 14, y: 3)`. Distinct from IG's edge-to-edge.
- **Photo**: inset 10pt inside the card, clipped to a 16pt rounded rectangle. Still 1:1 square, still double-tap to like, still swipeable carousel — just no longer bleeding to the screen edges.
- **Action row → pill row**: replaced the four floating glyphs with three warm cream (`cardSoft`) pills + a circular bookmark chip on the right:
  - `[♡ 23]` heart + count; accent color + `accentTint` fill when liked
  - `[💬 5]` `bubble.left` icon + count — note: glyph changed from `message` (IG) to `bubble.left` for a distinct silhouette
  - `[✈]` paperplane, no count
  - `[⚑]` circular bookmark chip, right-aligned
- **Likes count line deleted**: no more standalone "X 次点赞" above the caption. The count lives inside the heart pill now, saving ~20pt of vertical space.
- **Footer timestamp deleted**: redundant with the header timestamp. Header still shows relative time ("3小时前"); bottom of card is quieter.

### Follow button
- Plain text link → small accent-tinted pill: `accentTint` background + accent text for "关注"; hairline outline + secondaryText for "已关注". 12pt semibold, 10pt/5pt padding, continuous capsule. Pinterest-style compact pill.

### Stories bubble (`PetStoryBubble`)
- **Friend bubbles** gain a small species-emoji badge (🐶🐱🐰…) in the bottom-right, white-backed with a hairline stroke. Reads as pet-themed instead of a generic Instagram ring.
- Own-story "+" badge unchanged.

### SkeletonCard
- Rewritten to match the new floating-card look: 22pt corner radius, soft shadow, inset photo placeholder with 16pt radius, pill-shaped action stubs, circular bookmark stub. No pop when skeletons are replaced by real cards.

### Dead code removed
- `likesCountLine`, `likesCountText`, `uppercaseTimestamp`, `footerDateText` helpers deleted (no longer referenced).

## Files Changed

| File | +/− |
|---|---|
| `PawPal/Views/FeedView.swift` | ~+200 / -110 lines (page bg, floating cards, pill reactionRow, stories eyebrow + species badge, follow pill, SkeletonCard refresh) |
| `CHANGELOG.md` | this entry |
| `docs/known-issues.md` | refreshed spot checks |

## Validations

- ❓ `xcodebuild` — not available in authoring sandbox; **build verification still pending**
- ⚠️ Manual spot-checks pending:
  - Page background reads as warm cream, not stark white
  - Posts float as rounded white cards with a soft shadow and ~14pt horizontal inset
  - Photo is inset inside the card with rounded corners (not bleeding to the card edges)
  - Action row: three warm-cream pills on the left (like/comment with counts baked in, paperplane solo), bookmark as a circular chip pinned right
  - No standalone "X 次点赞" line above the caption; no absolute-date footer below the card
  - Tapping heart fills it with PawPal accent (`#FF7A52`) and flips the pill to `accentTint`; number ticks
  - Bookmark fills accent when tapped
  - Comment pill uses `bubble.left` (not IG's `message` tail-down-right)
  - Non-own posts show a small accent-tinted "关注" pill (not plain text)
  - Stories rail sits in its own rounded card with a "🐾 小伙伴动态" eyebrow
  - Friend's pet bubbles have a small species emoji (🐶/🐱/…) badge in the bottom-right with a white ring
- ✅ `xcodebuild test` — not run

---

## 2026-04-17 — Feed polish round: smaller reaction icons, menu-based delete, stories rail with own + friends' pets (#18)

## Summary

User feedback after the Instagram rewrite: (1) reaction icons too big, (2) delete affordance looks weird as a single-tap ellipsis, (3) top rail should show "your stories + friends' stories" instead of just your own pets. Addressed all three.

1 file changed, ~75 lines net.

## Changes

### Reaction row (`Views/FeedView.swift` — `reactionRow`)
- Heart / comment / bookmark reduced from 24pt → 20pt; paperplane 22pt → 19pt. Gap widened 14 → 16pt so spacing still reads open. Matches Instagram iOS icons more closely and stops the row from dominating the card.

### Own-post delete (`Views/FeedView.swift` — `cardHeader`)
- Replaced the flat ellipsis-as-tap-delete button with a proper `Menu` — ellipsis now opens a popover containing a destructive "删除动态" (with `trash` SF Symbol). Prevents accidental deletes and matches Instagram's own ellipsis-menu-then-item pattern. `.contextMenu` long-press still works as a backup. Ellipsis visual weight tuned to 15pt semibold inside a 32pt hit-target.

### Top rail → stories rail (`Views/FeedView.swift` — `PetsStrip`, `PetStoryBubble`, new `followedStoryPets`)
- **New `followedStoryPets` computed property** on `FeedView`: derives unique pets from `postsService.feedPosts`, excludes the user's own pets, sorts by most recent post. This is the "friends' stories" source since we don't yet have a dedicated stories backend.
- **`PetsStrip` API changed**: was `pets: [RemotePet]`, now takes `myPets: [RemotePet]` + `followedPets: [RemotePet]`. Renders `myPets` first (own pets, leading slot labeled "你的故事") then `followedPets` (friends' pets with activity).
- **`PetStoryBubble` additions**: new `isOwnStory` flag + optional `label`. Own stories render with a quiet hairline ring and a 20pt accent-colored "+" badge overlay at bottom-right (Instagram "your story" pattern). Friends' stories keep the conic-gradient ring with white inner gap.
- **Visibility rule**: the rail now shows as long as *either* your pets or followed pets with activity exist (was: only if you had pets).
- **Spacing**: HStack spacing 12 → 14 to accommodate the slightly wider "your story" badge.

## Files Changed

| File | +/− |
|---|---|
| `PawPal/Views/FeedView.swift` | ~+75 / -30 lines (reaction sizing, delete Menu, PetsStrip dual-section, PetStoryBubble own-story variant, new `followedStoryPets`) |
| `CHANGELOG.md` | this entry |
| `docs/known-issues.md` | refreshed spot checks for this pass |

## Validations

- ❓ `xcodebuild` — not available in authoring sandbox; **build verification still pending**
- ⚠️ Manual spot-checks pending:
  - Reaction icons visibly smaller / lighter than before — don't dominate the card
  - Tapping ellipsis on an own post opens a menu with "删除动态" (with trash icon); tap deletes; outside-tap dismisses
  - Long-press anywhere on an own-post card still shows "删除动态" (contextMenu fallback)
  - Top rail: first bubble is the signed-in user's first pet, labeled "你的故事", with a quiet hairline ring + orange "+" badge bottom-right
  - After own pet(s), followed pets with recent posts appear, ordered by most recent, with the conic gradient ring and pet name
  - If the user has no own pets but follows pets with activity → rail still appears (friends' stories only)
  - If the user has no pets and no follows → rail hidden (as before)
- ✅ `xcodebuild test` — not run

---

## 2026-04-17 — Feed: Instagram-style structural rewrite — edge-to-edge 1:1 photos, flat layout, spaced icon row, likes count, absolute-date footer (#17)

## Summary

User pushed back on the previous "polaroid" direction ("still not satisfied… make it more instagram like"). Previous card-with-shadow-and-tilt treatment was the wrong mental model entirely. Rewrote PostCard and the surrounding container to follow Instagram's visual vocabulary: edge-to-edge square photos, flat white page (no cards/shadows), a single row of spaced 24pt glyph icons (heart / comment-mirror / paperplane on the left, bookmark on the right), a bold-handle-inline-with-caption paragraph, and an absolute-date footer. Header got an Instagram-style hairline with three flat nav glyphs; stories rail got conic-gradient rings with a true white inner gap.

1 file changed, ~260 lines net.

## Changes

### PostCard (`Views/FeedView.swift`) — flat Instagram layout
- **Container**: dropped the rotated/offset/shadowed polaroid wrapper. `PostCard` now renders as a flat `VStack(spacing: 0)` on a plain `Color.white` backdrop, no corner radius, no shadow, no horizontal inset. Sits edge-to-edge like an Instagram post.
- **Header (`cardHeader`)**: 32pt circular avatar, handle 14pt semibold on line 1 with a 12pt tertiary timestamp to its right, species/mood on line 2 at 12pt secondary. On own posts a flat `ellipsis` SF Symbol replaces the "关注" pill; tapping it deletes (long-press still works via `.contextMenu`). On others' posts the follow affordance is a tap-only colored `关注` text link, no pill.
- **Image section**: `GeometryReader` determines the available width; both `singleImage` and `ImageCarousel` render at `side × side` (i.e. a true 1:1 square, full-bleed). `ImageCarousel` is now itself edge-to-edge — `TabView(.page(.never))` with a discreet dark pill badge top-right (`2/4`) and a centered row of 6pt/4pt white dots at the bottom, all overlaid inside the photo frame.
- **Reaction row (`reactionRow`)**: standalone row with 14pt spacing between heart / comment / paperplane on the left, bookmark pinned right via `Spacer(minLength: 0)`. All icons 24pt regular weight; heart fills red (`#ED2E40`) and scale-animates on like via `.contentTransition(.symbolEffect(.replace))`. Comment glyph is mirrored (`scaleEffect(x: -1)`) for the Instagram-style speech-bubble look. Paperplane is 22pt with 1pt vertical offset to align baselines.
- **Likes count line**: new `likesCountLine` prints "X 次点赞" above the caption, 14pt semibold, with Chinese `万`/`亿` formatting for large counts (1.2万, 3.4亿 etc.). Animates via `.contentTransition(.numericText())` on like/unlike.
- **Caption**: 14pt with an inline-bold handle (`currentProfile.username` for own posts, pet name fallback for others) prefixed to caption text via `Text + Text` concatenation. Line-clamped to 2 with a "更多" expand button that unfurls to full caption.
- **Timestamp footer**: `uppercaseTimestamp` rewritten to output *absolute* Chinese dates — "今天 HH:mm", "昨天 HH:mm", "M月d日", "yyyy年M月d日" — at 11pt uppercase, matching Instagram's footer convention. No longer a duplicate of the header time.
- **Comment preview (`commentPreviewSection`)**: stripped its container background; now a plain "查看全部 X 条评论" link followed by up to 2 preview rows of `<bold>handle</bold> comment`. All 13pt, no pill, no card.

### FeedView container + PetsStrip
- **FeedView body**: `LazyVStack(spacing: 0)` on white; removed per-post horizontal padding so posts go full-bleed. Only auxiliary widgets (banners, skeleton helper text, footer) retain padding.
- **Header**: white background with a bottom hairline; `PawPal` wordmark set to 26pt serif (was 30); three flat SF Symbol glyphs right-aligned (`magnifyingglass`, `heart`, `paperplane`) each 22pt regular.
- **PetsStrip**: horizontal padding tightened 20 → 12; HStack spacing 14 → 12.
- **PetStoryBubble**: rings resized 68pt → 64pt with conic-gradient + **white** inner gap (was cream — now reads as a proper Instagram story ring); avatar 56 → 54pt; name 12pt.
- **addPetBubble**: dashed placeholder circle resized to 64pt matching new story ring dimensions; "添加" label set to 12pt secondary.
- **SkeletonCard**: rewritten to mirror the flat layout — no card, 32pt avatar placeholder, square photo placeholder at full width, spaced action-row stubs — so skeleton→real handoff no longer pops.

## Files Changed

| File | +/− |
|---|---|
| `PawPal/Views/FeedView.swift` | ~+260 / -190 lines (PostCard rewrite, ImageCarousel edge-to-edge, new reactionRow/likesCountLine, absolute-date footer, Instagram-style PetsStrip + stories, flat SkeletonCard) |
| `CHANGELOG.md` | this entry |
| `docs/known-issues.md` | refreshed build-verification spot checks |

## Validations

- ❓ `xcodebuild` — not available in authoring sandbox; **build verification still pending**
- ⚠️ Manual spot-checks pending:
  - Posts render edge-to-edge; no card/shadow/rotation; photos are perfect 1:1 squares at full screen width
  - Action icons evenly spaced: heart / comment-mirror / paperplane on the left, bookmark far right
  - Heart fills red and count animates on tap; bookmark fills on tap
  - Likes line ("X 次点赞") renders above caption in 14pt semibold; large counts shorten to 1.2万
  - Caption starts with bold handle inline; "更多" expands past 2 lines
  - Footer shows absolute date ("今天 HH:mm", "昨天 HH:mm", "M月d日", "yyyy年M月d日"), *not* duplicate of header time
  - Stories rail: rings have white inner gap, ring sizing 64pt, tight 12pt horizontal padding
  - Header: white with hairline, 3 flat nav glyphs right-aligned
- ✅ `xcodebuild test` — not run

---

## 2026-04-17 — Feed PostCard: swipeable PhotoCarousel, inline-bold caption, drop menu/comment-card (#16)

## Summary

Follow-up to the alignment pass after user screenshot pushback ("You sure this looks the same???"). The first pass fixed spacing/shadows but missed five structural divergences in `PostCard` itself. Re-read the bundled HTML `PolaroidPost` (lines 1206-1309) + `PhotoCarousel` (lines 1014-1158) and brought the SwiftUI PostCard structurally in line.

1 file changed, ~90 lines net.

## Changes

### Feed PostCard (`Views/FeedView.swift`)

- **Multi-image layout → swipeable carousel**: replaced the `LazyVGrid` that stacked thumbnails in rows with a new `ImageCarousel` using `TabView(.page)`. Matches HTML `PhotoCarousel`: one photo visible at a time, swipe to page, 340pt tall.
- **Index badge** (top-right): `idx/count` pill with dark `rgba(26,22,20,0.6)` background, 11pt semibold, 10pt inset — mirrors HTML exactly.
- **Dot indicators** (below photo): 5pt inactive / 7pt active, 5pt gap, accent color for active / `#D9CFC2` for inactive. Animated via `.easeInOut` on index change.
- **Caption**: now prefixed with an inline-bold handle matching HTML `<b>{user.handle}</b> caption`. For own posts, uses `currentProfile.username`; falls back to pet name for others (owner profile isn't joined into `RemotePost` yet — tracked as known gap).
- **Ellipsis menu removed**: HTML `PolaroidPost` has no `···` button. Migrated the delete action to a `.contextMenu` on the whole card — long-press on an own-post reveals "删除动态". Visual matches HTML; functionality preserved.
- **Sub-row restyled**: dropped the two-color species/mood treatment (`secondaryText` + `accentSoft`) and unified to HTML's one-tone `#8B7C6D` with `#CCC` separator dot. Added a small sparkles icon before the mood. Kept species+mood content rather than `@handle · 📍 location` since we don't have owner handle or location on posts yet.
- **Comment-preview block**: stripped the `subtleSurface` card-within-a-card background. Now renders as plain inline text (13pt, muted) directly below the reaction row, matching HTML's `View all N comments` line.
- **Single-image height**: 300 → 340 (HTML `PhotoPlaceholder h={340}`).

## Files Changed

| File | +/− |
|---|---|
| `PawPal/Views/FeedView.swift` | ~+90 / -40 lines (new `ImageCarousel` struct, rewritten caption/sub-row/comment-preview/context-menu) |
| `CHANGELOG.md` | this entry |

## Validations

- ❓ `xcodebuild` — not available in authoring sandbox; **build verification still pending**
- ⚠️ Manual spot-checks pending:
  - Feed multi-image post swipes left/right, shows `1/3` badge top-right, dots update
  - Single-image post still renders at 340pt, no dots/badge
  - Caption renders `username caption text` with bold username
  - Long-press on own post shows "删除动态"; follow button gone on own posts
  - Tapping card (short tap) still navigates to PostDetailView
- ✅ `xcodebuild test` — not run

## 2026-04-17 — HTML prototype alignment pass: Feed spacing/shadow, Profile white bg, Chat title tracking (#15)

## Summary

Re-extracted the React/CSS source of truth from the bundled HTML prototype (the earlier refresh had misread some tokens) and corrected the SwiftUI implementation in the places that drifted. Focused on **layout & spacing** and **colors & gradients** per the user's priority. No behavior changes.

4 files changed, +38 / -25 lines.

## Changes

### Feed (`Views/FeedView.swift`)
- **PostCard**: removed the extra 0.5pt hairline stroke overlay on the polaroid card — the HTML `PolaroidPost` uses only a soft shadow (`0 2px 14px rgba(26,22,20,0.06)`), no border. The stroke was making cards read as "framed" rather than "floating paper".
- **PostCard shadow**: re-tuned from `radius: 10, y: 3` → `radius: 14, y: 2` to match the HTML `boxShadow`.
- **Header icons**: bumped from 16pt semibold → 18pt regular (HTML uses `size={20} strokeWidth={1.8/2}`); reduced header HStack spacing from 12 → 10 per HTML `gap: 10`.
- **Header title**: added `.lineLimit(1)` for safety at small widths.
- **PetsStrip padding**: reworked to match HTML `StoriesRow padding: '14px 20px 16px'` exactly — was unbalanced (4pt vertical + mismatched horizontal wrapper).
- **Feed structure**: moved the horizontal padding off the outer `LazyVStack` and onto individual post items (`padding(.horizontal, 20)` per post, following HTML's per-`PolaroidPost` wrapper `padding: '10px 20px 18px'`). This lets the `PetsStrip` scroll edge-to-edge as intended, rather than being clipped 20pt in on each side.
- **Footer text** ("今天的散步结束啦 🐾"): 13 → 12 to match HTML.
- **Timestamp tag**: added missing `.tracking(0.3)` (HTML `letterSpacing: 0.3`).
- **SkeletonCard**: aligned radius/padding/shadow with the real `PostCard` (radius 22 → 20, padding 16 → 14, shadow radius 8 → 14, y: 3 → y: 2, avatar 44 → 40, inner image radius 20 → 12). Prevents a visible pop as the skeleton is replaced by a real card.

### Profile (`Views/ProfileView.swift`)
- **Background**: changed from `PawPalBackground()` (warm cream radial gradient) → pure `Color.white`. HTML `ProfileScreen` explicitly uses `background: '#fff'`, distinct from Feed's `#FAF6F0`. Profile now reads as a clean gallery while Feed retains its warm journal feel.

### Chat (`Views/ChatListView.swift`)
- **Sticky header title** ("消息"): tracking `-0.6` → `-0.8` per HTML `ChatList` header `letterSpacing: -0.8`.

### Other notes
- **Auth, CreatePost, Discover** — these screens are not in the HTML prototype, so no alignment work was done for them. They remain SwiftUI-original designs.
- **MainTabView** — tab bar tint remains `PawPalTheme.accent` (warm orange) rather than HTML's `#1A1614` black-on-white, as the accent-tint tab bar is the established iOS convention and the HTML choice was stylistic.

## Files Changed

| File | +/− |
|---|---|
| `PawPal/Views/FeedView.swift` | ~30 lines changed (reformat of LazyVStack structure, token tweaks) |
| `PawPal/Views/ProfileView.swift` | 3 lines changed (background swap) |
| `PawPal/Views/ChatListView.swift` | 2 lines changed (tracking tweak) |
| `CHANGELOG.md` | this entry |

## Validations

⚠️ **Build verification pending** — xcodebuild isn't available in this environment. User should run:
```bash
xcodebuild -project PawPal.xcodeproj -scheme PawPal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```
Then spot-check: Feed header, pets-strip edge-to-edge scroll, post card shadow vs. previous border, Profile white background, Chat title kerning.

---

## 2026-04-17 — 2026 visual refresh: warm-cream design system, polaroid feed, virtual pet, redesigned chat (#14)

## Summary

Complete visual refactor of every primary screen (Feed, Profile, Virtual Pet, Tab bar, Chat) against a new prototype shipped by design. Replaces the bright orange-on-white palette with a warm cream + serif treatment, introduces a vector `DogAvatar` fallback, an interactive `VirtualPetView` stage on dog profiles, and rewrites the chat surface with a sticky glass header, online rail, sticker tray, and reaction overlays. Chinese-first copy is preserved.

10 files changed, +2680 / -610 lines.

## Changes

### Design System (`PawPalDesignSystem.swift`)
- **New token palette** — `accent` (#FF7A52), `background` (#FAF6F0), `cardSoft` (#F4F0ED), `subtleSurface` (#FAF7F4), `mint`, `amber`, `online`, `cool`, `berry`, plus `primaryText` / `secondaryText` / `tertiaryText` ink ramp and a `hairline` rule colour
- **Backward-compat aliases** — old `orange` / `orangeSoft` / `orangeGlow` / `pink` / `yellow` / `green` / `red` names kept so dependent files keep compiling
- **Components** — added `PawPalRadius`, `PawPalSpacing`, `PawPalFont`, `PawPalEyebrow`, `PawPalActionChip`, `PawPalStatBar`; refactored `PawPalAvatar` and `PawPalBackground` for the cream palette

### New Components
- **`DogAvatar.swift`** — vector geometric dog avatar with breed variants (golden, corgi, husky, shiba, beagle, poodle, pug), accessories (none / bow / hat / glasses), and expressions (happy / sleepy). `Variant.from(breed:)` matches both English and Chinese breed strings (柯基 / 哈士奇 / 柴 / 比格 / 贵宾 / 巴哥)
- **`VirtualPetView.swift`** — interactive virtual pet stage with thought bubbles, breathing animation, tail-wag, tap-to-boop with reaction emoji rise, mood/hunger/energy stat bars, and 喂食/摸摸/玩耍 action buttons firing medium haptics
- **`ChatDetailView.swift`** — sticky glass header with back chevron + presence subline, auto-scrolling message list, bubble groups with tap-to-react overlay (❤️/😂/😮/😢/🐾) and double-tap shortcut, sticker tray with 7 breed variants, composer with sticker toggle and accent send button, "typing…" indicator with pulsing dots, canned auto-reply

### UI Refactors
- **`MainTabView`** — switched Discover icon from `safari.fill` → `magnifyingglass`, Create from `plus.app.fill` → outline `plus.app`, accent retargeted to `PawPalTheme.accent`, tab bar set to `.automatic` material for liquid-glass feel
- **`FeedView`** — sticky glass header with serif "PawPal" wordmark + square white icon buttons, conic-gradient story rail (`PetStoryBubble`), polaroid `PostCard` with alternating tilt (-0.6° / 0.5°), DogAvatar + serif italic timestamp, new reaction chip group + bookmark button, enlarged 90pt heart-burst overlay, italic serif footer
- **`ProfileView`** — pet bubble now uses `DogAvatar` for dogs with accent ring on selection; new `featuredPetSection` renders `VirtualPetView` for dogs (seeded from `PetStats`) and falls back to `PetCharacterView` for other species; new Posts/Tagged tab strip with accent underline; converted post grid from 2-column cards to 3-column Instagram-style square tiles with like-count overlay
- **`ChatListView`** — full rewrite: sticky glass header with serif "消息" wordmark, cream-pill search, "在线" rail of online friends (DogAvatar + green dot), thread rows with handle / typing / time / unread badge, handles to push `ChatDetailView`

## Files Changed

| Folder | File | Status | Notes |
|---|---|---|---|
| Views | `PawPalDesignSystem.swift` | Rewritten | New token palette + components, backward-compat aliases |
| Views | `DogAvatar.swift` | New | Vector breed avatar with variants/accessories/expressions |
| Views | `VirtualPetView.swift` | New | Interactive virtual pet stage |
| Views | `ChatDetailView.swift` | New | Conversation detail with stickers + reactions |
| Views | `MainTabView.swift` | Modified | Icon swaps, accent retarget, glass tab bar |
| Views | `FeedView.swift` | Rewritten | Polaroid posts, story rail, sticky header |
| Views | `ProfileView.swift` | Modified | Virtual pet stage, Posts/Tagged tabs, 3-col grid |
| Views | `ChatListView.swift` | Rewritten | Sticky header, online rail, NavigationLink to detail |
| docs | `decisions.md` | Modified | New "2026 visual refresh" entry |
| root | `ROADMAP.md` | Modified | Phase 5 marked UI-complete; current-state updated |

## Validations

- ⚠️ Build not verified in simulator from this environment — `xcodebuild` is not installed in the Cowork sandbox. Static review of all touched files passed; deployment target (iOS 18.5) supports every API used (`onChange(of:)` single-closure form, `Task.sleep(for:)`, `.lineLimit(1...4)`, `AngularGradient`, etc.). Run locally before merging:
  ```bash
  xcodebuild -project PawPal.xcodeproj -scheme PawPal \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
  ```
- 🔲 Manual spot checks needed: Auth, Feed loading, Create post flow, Profile pet selection, Chat thread push + send/sticker/reaction
- 🔲 Pet avatar fallback chain (real photo → DogAvatar → emoji) needs visual confirmation on a real device with a non-dog pet

---

## 2026-04-14 — Pet avatar display in feed and pet profile, pet editor redesign ([#13](https://github.com/halflkaka/pawpal/pull/13))

## Summary

Renders pet avatar photos in Feed post cards and PetProfileView, redesigns the pet editor form with a custom unit picker and MapKit-powered city search, and removes the "贴贴" reaction button from PostCard.

4 files changed, +244 / -48 lines.

## Changes

### UI
- **Pet avatar in Feed** — `PostCard` loads `pet.avatar_url` via `AsyncImage`; falls back to species emoji on nil or load failure
- **Pet avatar in PetProfileView** — extracted `petAvatar` computed property with the same `AsyncImage` / species emoji fallback; extracted from `petHeader` for clarity
- **Reaction chip background** — changed from `PawPalTheme.background` to `PawPalTheme.cardSoft` for better contrast
- **Removed "贴贴" reaction button** — reaction row in `PostCard` no longer includes the hug chip

### Pet Editor Redesign
- **Custom unit picker** — replaced `Picker(.menu)` for age/weight units with a `Menu`-based `unitMenu` view; shows a checkmark next to the selected option and an orange capsule label
- **MapKit city search** — replaced free-text `homeCity` field with a `LocationPickerSheet` sheet backed by `MKLocalSearchCompleter`; shows real-time autocomplete results as the user types
- **Sex selector fix** — removed "未设置" option; fixed layout with `fixedSize` and `Spacer(minLength: 8)`
- **Field alignment** — `.multilineTextAlignment(.trailing)` now propagates into all `fieldRow` TextFields

### Display Helpers (PetProfileView)
- **`withUnit()`** — appends default unit (岁 / 公斤) to bare numeric values; values already containing CJK characters are returned unchanged
- **`localizedSex()`** — translates "Male" / "Female" DB values to "公" / "母" in tag pills

### Docs
- **ROADMAP** — Phase 4 items updated with ✅ markers and implementation detail

## Files Changed

| Folder | Files |
|---|---|
| `PawPal/Views/` | `FeedView.swift`, `PetProfileView.swift`, `ProfileView.swift` |
| `/` | `ROADMAP.md` |

## Validations

- ⚠️ **Build / tests** — results not available for retrospective PR

Tested with: `xcodebuild test -project PawPal.xcodeproj -scheme PawPal -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

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
