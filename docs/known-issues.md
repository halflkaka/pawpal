# Known Issues & Tech Debt

Things that are broken, deferred, or need attention. Keep this up to date as issues are resolved or discovered.

---

## Testing

- **`testCanAddPetAndSeeItInProfilesAndHome` always fails** — the test requires a logged-in Supabase session but there is no mock auth layer. It gets further than before (accessibility identifiers are wired up) but stalls at the pet name field. Fix requires either a `UI_TESTING` mock path in the app or a dedicated test account with pre-seeded data.

## Known Gaps

- **Migration 013 must be run before #38 features work** — CHANGELOG #38 depends on `supabase/013_pet_visits_and_boops.sql` (new `pet_visits` table, `pets.boop_count` column, and `increment_pet_boop_count` RPC). Until the migration is applied, `recordVisit`, `incrementBoopCount`, and `fetchBoopCount` all fail silently — visits won't record and the 访客 / 摸摸 cells will read 0. Apply via the Supabase SQL editor (or CLI). Spot checks after migration:
  - Open another user's pet → 访客 cell reads 1 on first visit, same after refresh same day, 2 after visiting on a new day
  - Tap the pet 10 times rapidly → 摸摸 cell jumps by 10 immediately; ~1.8s later one RPC fires; count persists after navigating away and re-opening
  - Open your own pet → 访客 does NOT increment (self-view skip works), tapping the pet does NOT increment 摸摸 (owner's onBoop is nil)
  - Rapid tap then immediate navigation → `.onDisappear` flushes the buffered delta; on re-open the count reflects it
  - Force an RPC failure (e.g. block network) → optimistic increment rolls back; UI doesn't show a count that was never persisted
  - Delete a pet → `pet_visits` rows cascade-delete (verify in SQL editor)
  - Boop counter survives across sessions and across different viewers — user A boops 5×, user B opens the profile and sees `摸摸 5`

- **Cross-view virtual pet sync — resolved in #43** — The chain of fixes #40 / #41 / #42 finally landed the definitive solution in #43: `VirtualPetView.externalAccessory` is a controlled input that the parent binds to the shared cache, and an internal `.onChange(of:initial:)` syncs it to `state.accessory` with a spring animation. Neither the bounce (re-init on every `.task` via `petReloadSeed`) nor the cache-only (works for fresh instances but misses the reverse direction) approaches from #40–#42 covered every case; the controlled-input pattern does. Animations, thoughts, and tap counts all survive cross-view accessory changes; pop-backs don't reset any internal state. If a regression is reported, verify that (a) `externalAccessory` is passed at both call sites, (b) migration 014 is applied, (c) `PetsService.shared` is used (not a new instance).

- **Virtual pet accessory + time-based bars need migration 014** — the virtual pet now persists its accessory choice (bow / hat / glasses) via `pets.accessory`, and the mood/hunger/energy bars shift with real time (hunger decays 3/hr since the last post; energy follows a time-of-day sine curve; mood decays slowly). Until `supabase/014_add_pets_accessory.sql` is applied, `updatePetAccessory` writes will fail silently and the dress-up state won't survive a revisit. Apply via the SQL editor, then spot-check:
  - Own pet: tap 🎩 → navigate away → return: hat is still on
  - Midnight visit: energy bar reads ~25-30% (sleepy)
  - Afternoon visit: energy bar reads ~85-90% (peak)
  - Pet with last post 24h ago: hunger ~30%; post a new picture → hunger jumps back to ~100% on next open
  - Pet with no posts at all: hunger sits at a neutral 60 (doesn't free-fall to 20)
  - Non-owner tries to dress up someone else's pet: write is rejected by `pets` UPDATE RLS; the local UI shows the accessory for this session but it won't persist

- **Feed/pet/play buttons: resolved in #45 (persisted via `pet_state`)** — #44 made the bars controlled inputs and stripped the local stat bumps to fix cross-view drift, but that left the buttons inert. #45 added migration 015's `pet_state` table and a `VirtualPetStateStore` that persists each feed/pet/play delta via optimistic upsert. Both profile screens prefer the persisted snapshot over the time-derived baseline, so a tap on 喂食 in `ProfileView` shows the same bar value in `PetProfileView` *and* survives relaunch. Visitor profiles still can't move bars (RLS rejects the write; client gates on `canEdit` too). If a regression is reported, verify (a) migration 015 is applied, (b) both screens observe `VirtualPetStateStore.shared`, (c) the pet id is passed to `VirtualPetView.petID`.

- **Build verification pending for PetProfileView virtual pet + changeable avatar** — CHANGELOG #37 brought the full interactive virtual-pet stage to `PetProfileView` and added a `PhotosPicker`-backed avatar edit affordance (owners only). The seeding logic was also extracted from `ProfileView` into a shared `RemotePet+VirtualPet.swift` extension. Needs simulator run. Spot checks:
  - Open your own pet from the Profile list → `PetProfileView` shows the VirtualPetView stage between the bio and the stats card (stats bars + feed/pet/play + thought bubble + tap-to-boop)
  - Open the same pet from the Feed → same stage with the same seeded numbers (PetStats.make reads from the pet's posts, not the logged-in user's)
  - Own pet's avatar shows the small orange camera badge in the bottom-right; other users' pet avatars show no badge
  - Tap the avatar on your own pet → `PhotosPicker` opens. Pick a photo → preview appears in the circle immediately, dimming overlay + spinner during upload
  - On upload success: preview clears, new avatar renders via `AsyncImage`, parent `ProfileView`'s cached `pets` list is also updated (because `PetsService.updatePetAvatar` patches the cached array)
  - On upload failure: preview clears, previous avatar_url is retained, red Chinese error caption ("上传失败,请再试一次") shows under the avatar
  - Cat profile: stage shows cat thoughts ("呼噜呼噜" / "窗外有鸟!"), accessory chips hidden, `PetCharacterView` cat illustration
  - Dog profile: stage shows `LargeDog` with accessory chips (bow/hat/glasses)
  - `.id(pet.id)` on the VirtualPetView resets internal state when switching between pets (boop counters don't bleed across)
  - `ProfileView` featured pet section still renders identically after the helpers were extracted (regression check — same seed values, same thoughts, same background colours per breed variant)

- **Storage bucket must be created manually** — `supabase/004_storage.sql` only contains comments; the `post-images` bucket is never created by migration. It must be created in the Supabase dashboard (Storage → New bucket → name: `post-images`, public read). `AvatarService` uses the same bucket for pet avatars, so if avatars display, the bucket already exists. If post images fail with a "Bucket not found" error it will now surface visibly in the create-post button bar.

- **Chat entry points — resolved in #46** — Two entry points now exist: (1) `PetProfileView` shows a "给主人发消息" pill for non-owner visitors who have an authManager in context (Feed + Profile paths do, PostDetailView doesn't); (2) `FollowListView` rows each carry a `发消息` shortcut reachable from the Profile stats 粉丝 / 关注 taps. Both call `ChatService.startConversation` (idempotent — re-opens existing threads) and push `ChatDetailView`. If a regression is reported, verify (a) `authManager` is threaded through the call site to `PetProfileView`, (b) `startConversation` returns a non-nil id (check `ChatService.errorMessage`), (c) the `navigationDestination(item:)` on the source screen actually fires its closure (a stale destination binding was the initial blocker during development). Note there's still no standalone "user profile" view, so follow-list rows link only to DMs, not to the user's own page. That's fine until we add a dedicated profile screen.

- **Chat realtime, stickers, reactions, unread, presence — deferred** — MVP ships text-only DMs. Realtime subscriptions, typing indicators, online dots, sticker tray, per-message reactions, and unread badges are intentionally out of scope for #45; the `messages` schema doesn't carry a `last_read_at` / `read_by` column yet, and the UI hides those affordances rather than faking them. When adding, grow the schema first (see migration 016 comments for the seam).

- **Virtual pet stats — persisted as of #45** — The time-of-day baseline from #39 is now just a fallback. When the `pet_state` row exists (migration 015) the bars read from it and each 喂食 / 玩耍 / 摸摸 tap writes a delta back via `VirtualPetStateStore.applyAction`. The store is a process-wide singleton (`VirtualPetStateStore.shared`) so a bump on one screen is visible on the other within the same run, and survives relaunch because it's backed by `pet_state`. Remaining gap: there's no periodic decay RPC — once a pet is "fed" the hunger bar stays at the posted value until the owner plays or feeds again. If passive decay becomes a requirement, add a scheduled cron / RPC that nudges `pet_state` rows toward the time-derived baseline every few hours.

- **Build verification pending for 2026 visual refresh** — the refactor (CHANGELOG 2026-04-17) was authored in an environment without `xcodebuild`. A local simulator build + manual spot checks (Auth, Feed, Create post, Profile, Chat) are still required before the work can ship.

- **Build verification pending for HTML alignment pass** — the follow-up pass (CHANGELOG 2026-04-17 #15) corrected Feed shadow/padding, Profile background, and Chat title tracking against the bundled HTML prototype. Needs local simulator run + eyeball comparison with the HTML. Recommended spot checks:
  - Feed: pet stories rail scrolls edge-to-edge (not clipped 20pt in)
  - Feed: post cards have only a soft shadow, no 0.5pt border
  - Profile: background is pure white, not the cream radial gradient
  - Chat: "消息" title reads slightly tighter than before

- **Build verification pending for text-only post variant** — CHANGELOG 2026-04-17 #20 branches `PostCard.body` on whether there are images. Text-only posts render a new 17pt `textOnlyCaption` directly below the header, with the pill action row sitting under the text. Subsequent passes retuned typography (#21, #22) and alignment (#23 → #24); current state is 15pt SF Pro medium with a 14pt horizontal pad (caption aligns with the avatar, not the handle). Needs simulator run. Spot checks:
  - Text-only post: caption appears directly under the handle/time line (no empty gap where an image would sit)
  - Text-only caption reads at a normal body size (15pt SF Pro medium, not rounded, not shouty)
  - **Caption's leading edge aligns with the avatar** — a vertical ruler through the avatar's left edge passes through the first character of the caption. Caption is **not** indented to the handle column
  - Long caption wrapping: every line starts at the 14pt inner edge (no hanging indent)
  - Image-post caption is unchanged — still starts at the 14pt inner edge (same x-coordinate, aligned with the image above)
  - Action pills sit below the text, not above it
  - Image posts are unchanged — photo between header and pills, caption below pills
  - Long text-only caption shows "展开" in accent color and expands fully on tap (threshold 240 chars)

- **Build verification pending for Feed redesign (break from IG)** — CHANGELOG 2026-04-17 #19 moved off the Instagram template: cream page background, floating white cards with inset rounded photos, action row converted to warm `cardSoft` pills with inline counts, follow as accent-tinted pill, stories rail wrapped in its own floating card with "🐾 小伙伴动态" eyebrow, and species emoji badges on friend bubbles. Standalone "X 次点赞" and footer-date lines removed. Needs simulator run. Spot checks:
  - Page reads as warm cream (`#FAF6F0`), not stark white
  - Each post is a floating white card, ~14pt horizontal inset, 22pt corner radius, soft shadow visible at 3pt offset
  - Photos are inset 10pt inside the card and have rounded corners (16pt) — they no longer bleed to the card edges
  - Action row: three pills on the left ([♡ count], [💬 count], [✈]) at warm `cardSoft` background; bookmark as a circular chip pinned right
  - Heart pill fills with `accentTint` background + `#FF7A52` heart icon when liked; count animates via numericText transition
  - Bookmark fills accent when tapped
  - Comment glyph is `bubble.left` (rounded square with tail bottom-left) — distinct from IG's `message`
  - No standalone "X 次点赞" line above the caption; no absolute-date timestamp footer below the card
  - Non-own posts show a small accent-tinted "关注" pill (10pt corner radius); when followed, it switches to a quiet hairline-bordered pill
  - Stories rail: floating white card with "🐾 小伙伴动态" eyebrow above; sits at the top of the cream page
  - Friend's pet bubbles have a small species emoji (🐶/🐱/🐰…) badge in the bottom-right with a white background and hairline ring
  - Skeleton cards match the new rounded floating-card look (no pop when replaced)

- **Build verification pending for Feed polish round** — CHANGELOG 2026-04-17 #18 shrank reaction icons, replaced the ellipsis-tap-delete with a Menu-based delete, and split the top rail into "your stories" + "friends' stories". Mostly superseded by #19 (the icon-sizing pass is moot now that they're inside pills, but the Menu delete and dual-section stories rail are kept). Spot checks:
  - Reaction row: heart / comment / bookmark render at 20pt, paperplane at 19pt — noticeably lighter than the previous 24/22pt pass
  - Own-post ellipsis now opens a Menu (not a direct delete). Menu shows one destructive item "删除动态" with a trash icon. Confirm tap outside dismisses without firing the delete
  - Own-post long-press contextMenu still works as a backup for delete
  - Top rail renders your own pets first with a quiet hairline ring and an orange "+" badge at the bottom-right; the first own pet is labeled "你的故事", subsequent own pets use the pet's name
  - Followed pets with recent feed activity appear after own pets, with conic-gradient ring + white inner gap
  - If the user has pets but follows nobody → only own-story bubbles render
  - If the user has no pets but follows pets with posts → only friends' stories render (no "your story" bubble)
  - If the user has neither → the rail is hidden entirely
  - No layout jumps when the feed reloads and `followedStoryPets` recomputes

- **Build verification pending for Instagram-style Feed rewrite** — CHANGELOG 2026-04-17 #17 rewrote `PostCard` + container as a flat Instagram-style layout (edge-to-edge 1:1 photos, no card/shadow/tilt, spaced 24pt action glyphs, "X 次点赞" line, absolute-date footer, white-inner story rings). Partially superseded by #18 (icon sizes, delete affordance, rail). Spot checks:
  - Posts render edge-to-edge (no horizontal inset); no card background, no shadow, no rotation
  - Photo area is a perfect 1:1 square at full screen width (use 3x screenshot + a ruler to confirm)
  - Action row: heart / comment-mirror / paperplane on left at 14pt spacing; bookmark pinned far right
  - Heart fills red `#ED2E40` on tap and scale-bounces; likes count ("X 次点赞") ticks via numeric transition
  - Large like counts collapse to Chinese format (e.g. `12345` → `1.2万`)
  - Caption reads `<bold>handle</bold> caption text` inline; clamped to 2 lines; "更多" reveals full text
  - Timestamp footer shows absolute date ("今天 HH:mm" / "昨天 HH:mm" / "M月d日" / "yyyy年M月d日"), NOT the same relative string as the header
  - Comment preview is a plain "查看全部 X 条评论" link plus up to 2 inline `<bold>handle</bold> comment` rows — no surrounding pill/card
  - Own-post ellipsis button (flat SF Symbol, not pill) deletes on tap; long-press on any own post also shows "删除动态"
  - Non-own post has plain colored "关注" text link, not a filled pill
  - Stories rail: ring 64pt with **white** inner gap (not cream), avatar 54pt, 12pt horizontal edge padding, 12pt between bubbles
  - Header: white with a hairline, PawPal wordmark 26pt serif, three flat glyphs right-aligned (magnifyingglass, heart, paperplane) at 22pt

- **Build verification pending for PostCard structural pass** — CHANGELOG 2026-04-17 #16 replaced the multi-image grid with a swipeable `PhotoCarousel`, added inline-bold caption handle, removed the `···` menu (delete via long-press contextMenu), restyled the sub-row, and dropped the comment-preview card background. Superseded in most visual aspects by #17, but the carousel mechanics (swipe paging, index badge) are preserved. Spot checks:
  - Multi-image post: swipe horizontally pages between photos; index badge updates `1/3 → 2/3 → 3/3`; dots reflect position; tapping card still navigates to PostDetailView (TabView swipe doesn't swallow tap)
  - Single-image post: no badge, no dots
  - Caption shows `<bold>username</bold> caption` for own posts; pet name for others

- **Owner profile not joined into RemotePost** — `loadFeed` selects `*, pets(*)` but doesn't pull in the post owner's `username`/`display_name`. As a result, the inline-bold caption handle uses `currentProfile.username` only for the user's own posts and falls back to pet name for others. Fix is to add a `profiles!owner_user_id(*)` join to `selectLevels` in `PostsService.swift` and surface it on `RemotePost`.

- **Build verification pending for species restriction (Dog/Cat only)** — CHANGELOG 2026-04-17 #36 trimmed the pet editor's species picker to Dog and Cat and narrowed the Discover filter tabs to 全部 / 狗狗 / 猫咪. Needs simulator run. Spot checks:
  - Add-pet sheet: species chip row shows only 🐶 Dog and 🐱 Cat (no rabbit/bird/hamster/other)
  - Edit-pet sheet: same chip row
  - Opening the editor on a legacy rabbit/bird/hamster pet: pet saves without errors; user can re-pick Dog or Cat if they want (but species string persists until they do)
  - Discover page: three filter tabs only (全部 / 狗狗 / 猫咪)
  - Feed / Contacts / Post detail cards still render legacy species emoji (🐰/🦜/🐹) for any existing pets with those species (defensive fallbacks untouched)
  - VirtualPetView with legacy species still renders via `PetCharacterView` and picks up species-aware thought copy

- **Build verification pending for VirtualPetView species support** — CHANGELOG 2026-04-17 #35 made the virtual-pet stage species-agnostic: cats/rabbits/birds/hamsters/"other" now render inside the same interactive chrome (feed/pet/play, stats, thought bubble, tap-to-boop) using `PetCharacterView` in place of `LargeDog`, with accessory chips hidden for non-dogs and species-aware thought copy. Needs simulator run. Spot checks:
  - Create a cat pet → profile shows VirtualPetView with cat illustration, mood/hunger/energy bars, feed/pet/play buttons. No 🎀/🎩/👓 chips in the header.
  - Feed/pet/play actions on a cat trigger the right animations (🍖 / ✨ / 🎾 reaction emoji, stats animate, thought swaps).
  - Tap-to-boop on a cat triggers heart pop + spring jump + "已经摸了 N 下" counter.
  - Idle thought rotation picks cat-flavoured copy ("呼噜呼噜", "窗外有鸟!", etc.), not dog thoughts.
  - Rabbit / Bird / Hamster / Other species each render with species-specific thought pool.
  - Existing dog flow is unchanged — accessory chips visible, LargeDog renders, breed-specific thoughts still work.
  - Pet-switcher (tap a different pet in the pets row) swaps the stage without state bleed across species.
  - Known limitation: the legacy `PetCharacterView` has no accessory rendering layer, so accessories remain dog-only. Not a regression — this was the behavior pre-#35 too.

- **Build verification pending for Profile grid photo-bleed + typography fix** — CHANGELOG 2026-04-17 #34 rewrapped the tile in `Color.clear.aspectRatio(1, .fit).overlay { … }.clipped()`, framed + clipped the AsyncImage explicitly, flattened the text tile's gradient fill, and tuned caption type down to 11.5pt with a 6-line clamp. Needs simulator run. Spot checks:
  - Image tile: photo is crisply bounded — no pink/photo bleed into the tile to its right (the issue from the previous screenshot)
  - Text tile: flat cream fill, no translucent fade at the bottom-right; looks clean on any backdrop
  - "如果我发一条纯文字，特别长的动态怎么办呢" tile: caption wraps in 3 lines instead of 4, no orphaned trailing syllable
  - Short captions ("Hi", "Hello World") still sit cleanly at the top with the quote glyph
  - Tile remains square; grid remains 3-column; tap still navigates to PostDetailView

- **Build verification pending for Profile grid text-only tile cleanup** — CHANGELOG 2026-04-17 #33 removed the `text.alignleft` placeholder glyph from text-only tiles, introduced a dedicated `textOnlyProfileTile` body with a soft gradient + accent quote glyph, and swapped the like-count badge into a translucent black pill. Superseded visually by #34 (the gradient fill is gone; the caption is 11.5pt now). The placeholder-icon removal and the dark-pill like badge are retained. Spot checks:
  - Text-only tile: small orange `quote.opening` at top-left, caption below it at 12pt semibold; no three-line glyph anywhere
  - Long caption tile ("如果我发一条纯文字，特别长的动态怎么办呢"): text wraps inside the tile; right edge doesn't clip mid-character; if it exceeds 5 lines it truncates with ellipsis
  - Like badge on text tile: dark translucent pill (0.55 opacity), `♡ 0` / `♡ 1` clearly readable
  - Like badge on image tile: same pill but lighter (0.38) so it doesn't dominate the photo
  - Grid remains 3-column, tiles remain square, tap navigates to PostDetailView

- **Build verification pending for VirtualPetView stage headroom pass** — CHANGELOG 2026-04-17 #32 grew the stage from 190 → 220 and moved the thought bubble back to top-trailing so its tail visibly points at the pet. Needs simulator run. Spot checks:
  - Thought bubble with no accessory — bubble is above-right of the dog, tail points toward the head, reads as emanating from the pet (not floating in a corner)
  - Equip 🎀 + thought — bow still on right ear tip, bubble sits above with clearance, both fully visible
  - Equip 🎩 + thought — hat on crown, bubble above with clearance, no overlap either way
  - Stage card overall height is taller but still balanced against statsRow and action tiles (30pt delta)

- **Build verification pending for VirtualPetView bubble+bow layout fix** — CHANGELOG 2026-04-17 #31 moved the thought bubble to the top-leading corner of the stage (was top-trailing after #30) so it no longer shares a rectangle with the hat/bow, and reseated the bow on the right ear tip. Superseded by #32 (bubble is back at top-trailing now that the stage is tall enough to give vertical clearance). The bow reseat to (130, 32) at 32pt is retained. Spot checks:
  - Equip 🎀 and trigger a thought — bubble is at top-left, bow sits snugly on the right ear tip, neither hides the other
  - Equip 🎩 and trigger a thought — bubble is at top-left, hat is centered on the head, no overlap
  - No accessory + thought — bubble is at top-left with 14pt top / 20pt leading padding
  - Reaction emoji (❤️/🦴/💤 on tap) still floats above the dog, unaffected

- **Build verification pending for VirtualPetView z-order fix** — CHANGELOG 2026-04-17 #30 reordered the `stage` ZStack so the thought bubble is declared after the pet VStack. Superseded in spatial behavior by #31 (bubble now top-leading), but the z-order itself is retained so the bubble text always wins in case of any residual overlap. Spot checks:
  - Tap 🎩 to put the top-hat on the dog, then tap the dog (or wait for a play action) to fire a thought — bubble text is fully visible; the hat brim/crown does not overlap the text
  - Reaction emoji (the ❤️/🦴/💤 that floats up on tap) is still on top of the dog — reorder only moved the thought bubble, not the pet+emoji group

- **Build verification pending for VirtualPetView breathing-room pass** — CHANGELOG 2026-04-17 #26 retuned spacing across header / stage+stats / actions and fixed the "5 years 岁" age-doubling bug in `ProfileView.formattedAge`. Needs simulator run. Spot checks:
  - Pet with English age (`"5 years"`, `"3 months"`, etc.) renders in Chinese ("5 岁", "3 个月"); existing Chinese values ("2 岁") unchanged
  - Virtual pet card: three visible chunks (header, stage+stats, actions), not a packed stack
  - Header row: 12pt gap between title column and accessory chips; chips have 8pt between them; title truncates before overlapping on narrow widths
  - Stats bars have a clear 16pt gap (not 12pt)
  - Action tiles are 14pt-padded with 10pt between them — read as proper buttons
  - "已经摸了 Kaka N 下" footer sits below the actions with breathing room

- **Build verification pending for Profile denser-header pass** — CHANGELOG 2026-04-17 #25 added a bio/prompt card, `编辑资料` + share action row, ghost add-pet bubble in the pets scroll, a three-card highlights strip (累计点赞 / 最新动态 / 陪伴天数), and replaced hard dividers with a hairline `softDivider`. Needs simulator run. Spot checks:
  - Header renders: avatar + name + handle, then bio card (prompt OR filled), then stats capsule, then `编辑资料` gradient pill + share circle
  - Bio prompt state (no bio) is the accent-tinted card with sparkle glyph + chevron; tapping opens the edit sheet
  - Bio filled state shows the bio text with a quote glyph and pencil affordance on the right
  - Pets row: scrolling past real pets reveals a dashed accent "+" bubble labeled "添加宠物"; tapping opens the add-pet sheet (same as the header add button)
  - Highlights strip shows three cards with distinct tints; values populate from real data. With 0 posts, `最新动态` shows "尚未发布"; with 0 pets, `陪伴天数` shows "—"
  - Soft divider visible as a short hairline between sections (not full-bleed)
  - ShareLink opens the system share sheet; URL is `pawpal://u/<handle>` (acceptable placeholder)
  - Account editor sheet opens from 3 places without duplicating or layering: header gear menu, bio row, `编辑资料` pill

---

## Recently Resolved

- **Post images never saved or displayed** — `RemotePostImage`, the PostgREST select strings, and the `post_images` INSERT struct all used column names `image_url`/`sort_order` instead of the actual live DB column names `url`/`position` (established by migration `011_align_post_images_columns.sql`). This caused every `post_images` SELECT to fall back to the bare `*, pets(*)` level (no images) and every INSERT to be rejected. Fixed column names throughout; also hardened the `position` field to `Int` (was `String`), added rollback-on-failure for image uploads, and surfaced upload errors in the always-visible button bar (2026-04-12).
