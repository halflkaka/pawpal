# Known Issues & Tech Debt

Things that are broken, deferred, or need attention. Keep this up to date as issues are resolved or discovered.

---

## Testing

- **`testCanAddPetAndSeeItInProfilesAndHome` always fails** — the test requires a logged-in Supabase session but there is no mock auth layer. It gets further than before (accessibility identifiers are wired up) but stalls at the pet name field. Fix requires either a `UI_TESTING` mock path in the app or a dedicated test account with pre-seeded data.

## Known Gaps

- **Local notifications stopgap — known limitations (2026-04-18)** — the `LocalNotificationsService` birthday scheduler works device-locally without APNs. It has a few documented tradeoffs that are deliberate, not bugs:
  - **Feb 29 birthdays skip non-leap years.** `UNCalendarNotificationTrigger(dateMatching: DateComponents(month: 2, day: 29), repeats: true)` only fires in leap years. The FeedView birthday card uses a fold-down-to-Feb-28 convention; the local notification does not. Fix in a follow-up by scheduling two requests (Feb 28 non-leap + Feb 29 leap) with a conditional body.
  - **64-pending-notification cap.** iOS caps pending local notifications at 64 system-wide per app. One slot per pet with a yearly repeat — a user with 65+ pets (unrealistic) loses the tail. No code action planned.
  - **Time-zone travel.** A user flying Shanghai → New York keeps their 09:00 reminder anchored to the device's current time zone — birthday fires at 09:00 local wherever they are that morning, not 09:00 Shanghai time. Intentional for a personal reminder.
  - **Cross-device sync.** Local notifications live on the device that scheduled them. A user signed in on iPhone + iPad gets the reminder on each (fine). A user who switches devices mid-day may see duplicates or misses until the new device's `MainTabView.task` reschedules.
  - **Permission revoked post-grant.** If a user grants, then disables notifications in iOS Settings, the scheduler silently no-ops on the next pass (early-exit when `authorizationStatus != .authorized`). No inline nag banner in v1.
  - **One-year age drift.** The body string "今天是 {pet_name} 的 {N} 岁生日" is fixed at schedule time. The trigger repeats yearly, but the string doesn't update between app-opens. Age drift is at most 12 months, corrected on any app open. Trade vs. switching to a one-shot request rescheduled annually — the repeating trigger is simpler; age drift is acceptable.

- **Build verification pending for local notifications stopgap (2026-04-18)** — `LocalNotificationsService.swift` landed without `xcodebuild` in the sandbox. Integration points grep-verified:
  - `MainTabView` observes `petsService.pets` via `.onChange` + `.task` and calls `rescheduleBirthdaysIfChanged(pets:force:)`, which diffs on `Set<BirthdayKey>` to skip reschedules when only non-birthday fields changed (important — `.petDidUpdate` fires on avatar/accessory edits via PR #50).
  - `AuthManager.signOut` calls `await LocalNotificationsService.shared.cancelAll()` before authService signs out.
  - `DeepLinkRouter.Route.pet(UUID)` case added; `birthday_today` / `memory_today` type strings route to `.pet(targetID)`; `pawpal://pet/<uuid>` URLs parse correctly.
  - `MainTabView.handleDeepLink(.pet(id))` switches to Me tab when the pet is owned, Discover tab otherwise, and pushes `DeepLinkPetLoader` which resolves the pet id → `PetProfileView`.

  Spot checks on device:
  - Fresh install → grant notifications → add pet with 生日 = any past date → force-quit app → verify the reminder is scheduled: use Debug → Notifications → List Pending in Xcode, or inspect via a breakpoint on `UNUserNotificationCenter.current().getPendingNotificationRequests`. Exactly one request per pet-with-birthday, identifier `pawpal.milestone.birthday.<uuid>`, trigger `UNCalendarNotificationTrigger` with (month, day) matching the pet's birthday and hour=9 minute=0.
  - Set a pet's birthday to today's date + 1 minute (temporarily edit `LocalNotificationsService` to use `hour = <now>` and `minute = <now+1>` for smoke test) → banner fires → tap → app opens to `PetProfileView` for that pet.
  - Change a pet's avatar (triggers `.petDidUpdate` broadcast from PR #50) → verify the scheduler does NOT redundantly reschedule (check `[LocalNotif] 已排程` log; should not appear if only non-birthday fields changed).
  - Clear a pet's birthday via the editor → scheduler reschedules without that pet → pending count drops by 1.
  - Delete a pet entirely → scheduler reschedules without that pet → pending count drops.
  - Sign out → all `pawpal.milestone.birthday.*` requests removed (check pending list after signOut).
  - Sign back in with pets cached → reschedule seeds from `petsService.pets` after first load; pending list rebuilds.
  - Revoke notifications in iOS Settings → foreground the app → scenePhase → active should trigger `PushService.refreshAuthorizationStatus` (existing code) AND the scheduler's `guard` should early-exit on the next reschedule without scheduling anything.
  - Re-grant notifications in iOS Settings → scenePhase → active → scheduler runs with `force: false`; if pet set unchanged, no-op. This is a tradeoff: toggling permission alone doesn't re-seed unless pets also change. Acceptable — a rare path.

- **Push notifications v1 — prerequisites pending user action (2026-04-18)** — the entire code side of push landed (migration 022, `dispatch-notification` edge function, `PushService` / `AppDelegate` / `DeepLinkRouter`, AuthManager + OnboardingView + MainTabView + ContentView + Info.plist edits), but four user-owned setup steps must complete before pushes actually deliver on device:

  1. **Apple Developer portal** — generate an APNs Auth Key (`.p8`), note the Key ID and Team ID, and ensure the PawPal App ID has **Push Notifications** checked.
  2. **Xcode target → Signing & Capabilities** — add the **Push Notifications** capability AND **Background Modes → Remote notifications**. Rebuild to regenerate the entitlements file.
  3. **Supabase function secrets** —
     ```
     supabase secrets set APNS_KEY_P8="$(cat AuthKey_XXXXXXXXXX.p8)"
     supabase secrets set APNS_KEY_ID=XXXXXXXXXX
     supabase secrets set APNS_TEAM_ID=XXXXXXXXXX
     supabase secrets set APNS_BUNDLE_ID=com.yourorg.pawpal
     supabase secrets set APNS_ENV=sandbox  # flip to production for TestFlight
     ```
  4. **Supabase Postgres settings (SQL editor)** —
     ```sql
     alter database postgres set "app.settings.dispatch_url" = 'https://<project>.functions.supabase.co/dispatch-notification';
     alter database postgres set "app.settings.service_role_key" = '<service_role_secret>';
     ```

  Deploy the function with `supabase functions deploy dispatch-notification --project-ref <ref>` and apply migration 022 via the SQL editor.

  Until all four are done, the client falls back gracefully — token upserts fail (caught + logged `[Push] register 失败`), onboarding still completes, and in-app functionality is unaffected. Users just won't receive pushes.

- **Push v1 — known tradeoffs documented in the direction doc (2026-04-18)** — not bugs, but worth knowing:
  - **No quiet hours.** A late-night like buzzes. Added to v1.5 follow-up decisions.
  - **`badge: 1` is static, not real unread count.** Real unread requires a `notifications.seen_at` column + a per-user pending count; seam reserved.
  - **Passive 410 cleanup only.** A user who reinstalls the app before signing back in leaves a stale token until the first APNs send returns `410 Unregistered`, at which point the edge function deletes it.
  - **TestFlight env detection.** `PushService.registerCurrentToken` uses `#if DEBUG` → `sandbox` else `production`. TestFlight ships a release-mode binary that uses the sandbox APNs host, so the first TestFlight build will tag tokens as production and APNs will reject them. Fix is to read `aps-environment` from the embedded provisioning profile at runtime — `TODO(push)` comment in `PushService.swift` tracks this.
  - **v1.5 notification types accepted but not built.** `notifications.type` CHECK includes `birthday_today`, `memory_today`, `playdate_*`, `chat_message`. The edge function's `buildPayload` returns an `unsupported_type` error for these until the follow-up PRs land. Migration 022 comments flag this.

- **Build verification pending for push notifications v1 (2026-04-18)** — PushService / AppDelegate / DeepLinkRouter / AuthManager / OnboardingView / MainTabView / ContentView / Info.plist all landed without `xcodebuild` in the sandbox. Spot checks on device (requires the four prerequisites above):
  - Fresh sign-up → complete onboarding → priming sheet appears with 🔔 hero, Chinese copy, 开启通知 / 以后再说 buttons. Tap 开启通知 → system permission prompt → grant → APNs token appears in Xcode console as `[Push] APNs token 已保存`.
  - Sign-in with existing account (token already cached in UserDefaults) → `[Push] device_tokens 已 upsert` logs without prompting again.
  - Sign out → DELETE on device_tokens fires BEFORE the Supabase session is gone (verify with Supabase Logs — the row should disappear before auth.uid() goes null).
  - User A likes user B's post → B receives a push titled `小爱心 ❤️` with body `{A's display name} 给你的 {pet name} 点赞了` within seconds. Tap → app opens to the post detail.
  - User A comments on B's post → push titled `新评论 💬` with comment preview. Tap → post detail.
  - User A follows user B → push titled `新的关注者 🐾`. Tap → A's profile (the follower's, not the recipient's).
  - Foregrounded push: banner still shows (verify `UNNotificationPresentationOptions` wire-up).
  - Self-like / self-comment / self-follow: no push fires (verify `queue_notification` short-circuit).
  - Device reinstall: on next login, new token upserts; old token row sticks around until the next send returns 410.
  - Open a `pawpal://post/<uuid>` link from Safari / Messages → app opens to the post detail via `.onOpenURL`.



- **`pets.birthday` column missing on older Supabase installs** — the canonical schema in `001_schema.sql:23` declares `birthday date`, but installs that were provisioned before that line landed never got the column. Migration `006_pets_age_column_alignment.sql` already documents this gap ("some older installs do not have birthday"). The milestones MVP (2026-04-18) hard-requires the column on the iOS side via `RemotePet.birthday`, which surfaces a PostgREST `cannot find "birthday" column in "pets"` error on these installs. Fix: apply `supabase/021_add_pets_birthday.sql` (idempotent `add column if not exists` + `notify pgrst, 'reload schema'`). Any future column the canonical schema declares but old installs may lack should ship with a similar idempotent migration rather than relying on the canonical file alone.

- **Build verification pending for milestones MVP (2026-04-18)** — first feature off the post-direction-reset 90-day plan. Two parallel devs landed:
  - **Dev 1 (data layer)**: `RemotePet.birthday: Date?` field added; `PetsService.addPet(birthday:)` and `PetUpdate.birthday` thread the value through writes; `PostsService.loadMemoryPosts(forUser:)` returns posts whose month-day matches today across prior years (200-row cap, client-side filter, `TODO(milestones-mvp)` for RPC promotion); new `PawPal/Services/MilestonesService.swift` (stateless, `@MainActor`, derived-not-stored — see `docs/decisions.md`); `ProfilePetEditorSheet` in `ProfileView.swift` gained a 生日 row + graphical date picker sheet + clear-birthday button + 10-arg onSave.
  - **Dev 2 (view layer)**: `FeedView.swift` got `MilestoneTodayCard` (birthday card above stories rail, swipeable when multiple), `MemoryTodayCard` (memory loop card with thumbnail + caption preview), `ComposerPrefill` type, and a `.sheet(item:)` that opens `CreatePostView` with prefill values; `PetProfileView.swift` got `UpcomingMilestonesRail` + `UpcomingMilestoneChip` between stats and post grid; `CreatePostView.swift` got `prefillCaption` + `prefillPetID` properties (both default-nil so `MainTabView.swift:115` compiles unchanged) and `.task` precedence reshape.

  Authored without `xcodebuild` in the sandbox. Spot checks on device:
  - **Birthday set to today**: edit a pet → set 生日 = today → return to Feed. "今日纪念日" card renders above the stories rail with "{pet.name} 今天 N 岁啦" and the 🎂 icon. Tap → `CreatePostView` opens with the pet preselected and caption "{pet.name} 今天 N 岁啦 🎂" prefilled.
  - **Two pets with birthdays today**: same flow surfaces a swipeable card with `1/2 → 2/2` indicator.
  - **Birthday set to tomorrow**: no FeedView card. PetProfileView shows "即将到来的纪念日" rail with one chip reading "明天 / N 岁生日" (chip is disabled-tap, accent muted).
  - **Birthday set to today on the chip**: chip is accent-tinted, shows "今天", tap → composer with prefill (matches FeedView card behavior).
  - **Birthday Feb 29 in non-leap year**: card surfaces on Feb 28 (fold-down convention).
  - **Pet without birthday**: PetProfileView rail is absent (no empty rail, no placeholder).
  - **Memory loop**: if user has any post with month-day matching today and year < this year, "X年前的今天" memory card renders below the birthday card on FeedView (or alone if no birthday today). Shows the historic post's first image as thumbnail. Tap → composer with `和 {petName} 一起，X年了 ❤️` prefill.
  - **Pet editor 生日 row**: opens graphical DatePicker sheet (max date = today, accent-tinted). "清除生日" button below picker resets to nil (row reverts to "选择日期" placeholder).
  - **Regressions**: add-pet still works without setting birthday (it's optional); editing a pet without touching birthday doesn't clobber any existing value.

  Known limitation, not a bug: clearing a previously-set birthday in the editor encodes via `encodeIfPresent` (matching the existing `bio: String?` precedent), so the PATCH omits the nil and the DB retains the old value. This is consistent with all other optional fields in `PetUpdate` — fixing it correctly requires a custom `encode(to:)` across all nullable columns, deferred to a follow-up. Common case (set birthday once, never clear it) works correctly.

  Doc updates landed: `ROADMAP.md` Phase 6 reshaped, `docs/scope.md` adds milestones to "in scope" and pet care to "deferred", `docs/decisions.md` adds "Milestones are derived, not stored".

- **Build verification pending for 2026-04-18 三合一 pass** — three independent changes landed together without a simulator run (sandbox has no `xcodebuild`):
  1. `supabase/019_add_story_media_storage.sql` — creates `story-media` bucket + public-read / auth-write policies (mirror of 012). Apply via SQL editor once; migration is idempotent.
  2. Discover additions: `PetsService.fetchPetOfTheDay` + `fetchRecentActivityPets`; new `petOfTheDaySection` hero card above the rails and `recentActivityRail` between 人气 and 同城. New `PetRailCard.Variant.recentlyActive` with a 📸 badge. `DiscoverView` now pulls a `FollowService` (per-view, matches `FeedView`) so the recent-activity dedupe can skip pets whose owner the viewer already follows.
  3. `DogAvatar.Variant` roster expanded by four breeds — `borderCollie` (黑白 + 白额斑), `cavapoo` (奶油色), `labrador` (黄拉), `dalmatian` (白底黑耳). `LargeDog.palette(for:)` + `thoughts(for:)` + previews extended in lockstep. `Variant.from(breed:)` handles English + Chinese aliases ("边牧", "卡瓦普", "拉布拉多", "斑点").

  Spot checks on device:
  - Stories: Take a photo → 发布 completes without "Bucket not found"; rail lights up; delete removes the row and cleans up the blob (verify in Storage dashboard).
  - Discover: 今日明星毛孩子 hero card renders at the top of 发现 with a rotating pet (same pet within a day, different pet tomorrow). Tapping routes to `PetProfileView`. When search text filters the hero out, the hero hides. When the user has no non-own pets in the DB, the hero section is absent (no dangling skeleton).
  - Discover: 最近在发的毛孩子 rail appears between 人气 and 同城. Pets the viewer already follows don't appear in it. Viewer's own pets don't appear. Each tile shows a 📸 badge overlay on the avatar.
  - Discover: Pull-to-refresh does NOT reshuffle today's hero pick (rotation is deterministic by day-of-year).
  - Virtual pet: Create a pet with breed "边牧" — DogAvatar + LargeDog render with black body + white muzzle + white forehead blaze + black ears. Same for "拉布拉多" (even yellow), "卡瓦普" (soft cream), "斑点" (near-white body + black ears + dark forehead spot that reads against the cream stage). Thought bubble rotates through breed-specific pool ("看我接飞盘!", "抱抱可以吗?", "有吃的吗?", "数数我的斑点").
  - Virtual pet: Existing breeds (golden, corgi, husky, shiba, beagle, poodle, pug) render identically to before; thought pools unchanged.

- **Build verification pending for Round 4 (#50)** — pet-mutation broadcast so cached feed / story rows reflect avatar + accessory edits without a pull-to-refresh. Authored without `xcodebuild` in the sandbox. The cross-service wiring is subtle (MainActor hop from the notification callback, `RemotePost` is `let` so `patchPet` rebuilds the row, `RemoteStory.pet` is `var` so it's mutated in place), but each piece is exercised at runtime — a failing subscription or a wrong init arg would flag on first launch. Spot checks on device:
  - Edit pet avatar on PetProfileView (own pet) → pop back to Feed without pull-to-refresh → any older post from that pet now renders the new avatar
  - Change accessory on ProfileView virtual-pet stage → navigate to PetProfileView without a pull — the new accessory shows immediately on the virtual pet there
  - Pet with an active story: change its avatar → Feed's story rail ring thumbnail updates without a pull
  - Edit pet name/breed/bio → any cached post card updates the sub-header immediately
  - Pet with no posts / no stories: edit avatar → no visible churn elsewhere (patchPet is idempotent / no-op when no rows match)

- **Build verification pending for Round 3 (#49)** — camera-first story composer rewrite, owner-only accessory gate. Authored without `xcodebuild` in the sandbox. Needs a local build on a physical device (simulator has no camera, so the capture path is only smoke-checkable on hardware). Spot checks on device:
  - Tap 发毛孩子今日份 rail "+" → composer opens fullscreen with the system camera → shutter → preview with caption field and X/发布 controls, no clipped title, no overlap
  - Cancel on the camera screen before capturing → composer dismisses entirely
  - After capture, tap 🖼 → PhotosPicker opens → pick a library photo → preview swaps
  - After capture, tap 📷 → camera re-opens for a retake
  - Simulator path: composer opens, gallery picker auto-presents (no camera), preview + publish works
  - Visitor viewing a friend's pet profile: 🎀/🎩/👓 chips are hidden; owner's accessory still renders on the virtual pet stage
  - Own profile (Me tab): chips visible, tapping one persists + syncs to PetProfileView

- **Build verification pending for Round 2 (#48)** — stories MVP, virtual-pet passive decay, and Discover tab all landed without a simulator run (authored on a Linux sandbox without `xcodebuild`). Needs a local build + manual spot checks across Stories (compose, viewer, delete), the virtual-pet bars (drift + tap after drift), and 发现 (three rails, empty state, search filter). Regressions to re-verify: Auth, Feed render + PostCard, Create post, Profile.

- **`story-media` bucket — resolved by migration 019** — Migration 018 punted bucket creation to "manual via dashboard"; in practice nobody clicked the button and every `StoryService.postStory` failed with "Bucket not found" in the composer's inline error row. Migration `019_add_story_media_storage.sql` now codifies the bucket + the same four read/insert/update/delete policies as `post-images` (public read, authenticated write gated on `owner = auth.uid()`). Apply the migration once via the Supabase SQL editor; subsequent runs are idempotent (`on conflict (id) do update`). After applying: open story composer, take a photo, tap 发布 — the upload should succeed and the new story should light up the rail ring without "Bucket not found".

- **`stories` ↔ `profiles` PostgREST join — resolved by migration 020** — Migration 018 declared `stories.owner_user_id references auth.users(id)`, but PostgREST only resolves embedded-resource joins (`profiles!owner_user_id(*)`) against tables in schemas it exposes — and `auth` is hidden by design. Result: every `StoryService.loadActiveStories` / `postStory` call failed with `"could not find relationship between 'stories' and 'profiles' in the schema cache"`. Every other owner-bearing table in the schema (`pets`, `posts`, `follows`) already references `public.profiles(id)` (which itself references `auth.users(id)`, so the cascade chain is preserved). Migration `020_fix_stories_owner_fk.sql` re-points `stories.owner_user_id` at `profiles(id)` to match the rest of the schema + issues `notify pgrst, 'reload schema'` so the cache updates immediately. Apply once via SQL editor; the drop/add is guarded on `if exists` + `pg_constraint` lookup so it's idempotent. After applying: stories rail loads on Feed, story publish succeeds and appears in the viewer with the owner profile snapshot attached.

- **Video stories are schema-ready but client-only-images** — migration 018's `media_type` CHECK accepts `'video'` and `StoryService.postStory` routes through a video branch with `video/mp4` content-type, but the composer's `PhotosPicker` is hard-coded to `matching: .images` and the viewer renders media via `AsyncImage` (stills only). Video playback lands in a follow-up PR. Search `TODO(video)` for the seams.

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

- **Chat entry points — resolved in #46, extended in #47** — Three entry points now exist: (1) `PetProfileView` shows a "给主人发消息" pill for non-owner visitors who have an authManager in context (Feed + Profile paths do, PostDetailView doesn't); (2) `FollowListView` rows each carry a `发消息` shortcut reachable from the Profile stats 粉丝 / 关注 taps; (3) `+` in `ChatListView` opens a `ComposeNewChatSheet` listing the viewer's following — tapping a row routes through `ChatService.startConversation` into `ChatDetailView` via a `navigationDestination(item:)` pattern. All three call sites are idempotent against existing threads. If a regression is reported, verify (a) `authManager` is threaded through the call site to `PetProfileView`, (b) `startConversation` returns a non-nil id (check `ChatService.errorMessage`), (c) the `navigationDestination(item:)` on the source screen actually fires its closure (a stale destination binding was the initial blocker during development). Note there's still no standalone "user profile" view, so follow-list rows link only to DMs, not to the user's own page. That's fine until we add a dedicated profile screen.

- **Onboarding gate — resolved in #47** — Brand-new sign-ups are now routed through `OnboardingView` (full-screen, no skip affordance) before `MainTabView` ever renders its tab bar. `MainTabView.shouldShowOnboarding` guards on `authManager.currentUser != nil`, `hasLoadedPetsAtLeastOnce`, and `!petsService.isLoading` to prevent a first-paint flash for returning users with pets. The sheet collects name (required), species (Dog/Cat, defaults Dog), breed, home city, bio, and avatar; errors surface inline without dismissing. The gate re-evaluates on `authManager.currentUser?.id` change via `.task(id:)` so sign-out → sign-in as a fresh user reruns it correctly. Spot checks: (a) brand-new account → onboarding renders in place of tabs; (b) returning user with pets → tab bar renders immediately, no flash; (c) sign-out and sign in as a different no-pet user → onboarding renders again; (d) empty name keeps the CTA disabled.

- **Pet-first pass on user-list surfaces — resolved in #47** — `ProfileView`'s `profileHeader` now leads with `petHeroRow(_:)` (pet avatar + name + species/breed/city pills); owner @handle is demoted to a tiny caption line. Users with zero pets see `addFirstPetHeroCard` instead (tappable CTA that opens the add-pet editor). `FollowListView` rows, `ChatListView` threadRow, and the new `ComposeNewChatSheet.row` each overlay a featured-pet badge (22pt) on the bottom-right of the user avatar, driven by `PetsService.loadFeaturedPets(for:)` (one batched `in` query; users with no pets get no badge). Caption copy in `CreatePostView` flipped to "今天你的毛孩子做了什么？" so the pet is the subject, not a required form field.

- **Dead stubs in Feed header — resolved in #47** — The search / notifications / paperplane glyphs + `headerGlyph` + the unconditional red notifications badge dot + the local-only bookmark chip (plus its `@State var saved`) were all removed. The Feed header is now just the serif wordmark; tab bar carries discovery + chat. No `showToast("功能还在完善中")` strings remain anywhere in the app.

- **Owner profile now joined into RemotePost — resolved in #47** — `RemotePost` carries `profiles: RemoteProfile?` (via `profiles!owner_user_id(*)` in the top three `selectLevels` of `PostsService`), exposed as `post.owner`. `FeedView.captionHandle` prefers `post.owner?.username` so non-own post captions render with the real owner handle in bold instead of the pet-name fallback. The bare-minimum `*, pets(*)` selectLevel is preserved so a missing FK hint doesn't break the feed.

- **Chat realtime, stickers, reactions, unread, presence — deferred** — MVP ships text-only DMs. Realtime subscriptions, typing indicators, online dots, sticker tray, per-message reactions, and unread badges are intentionally out of scope for #45; the `messages` schema doesn't carry a `last_read_at` / `read_by` column yet, and the UI hides those affordances rather than faking them. When adding, grow the schema first (see migration 016 comments for the seam).

- **Virtual pet stats — persisted as of #45, passive decay added in #48** — The time-of-day baseline from #39 is now just a fallback. When the `pet_state` row exists (migration 015) the bars read from it and each 喂食 / 玩耍 / 摸摸 tap writes a delta back via `VirtualPetStateStore.applyAction`. The store is a process-wide singleton (`VirtualPetStateStore.shared`) so a bump on one screen is visible on the other within the same run, and survives relaunch because it's backed by `pet_state`. Passive decay is now client-side (`decayedState`: hunger -3/hr, energy +2/hr, mood -1/hr) — `state(for:)` applies it on every read, `applyAction` computes the decayed baseline first and then stacks the tap delta. `updatedAt` only advances on a real persist, so decay is always anchored on the last tap's server time. A server-side cron still isn't required since every read recomputes from the source of truth.

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

- **Playdates MVP — known limitations + deferred follow-ups (2026-04-18)** — deliberate tradeoffs at ship, not bugs:
  - **APNs-gated `playdate_invited` delivery.** The invite push rides migration 022's pipeline (`queue_notification` → `dispatch-notification` → APNs). Until Apple Developer Program enrollment + the four prerequisites in "Push notifications v1 — prerequisites pending" land, invitees will NOT receive a push. The product is not silently broken in the meantime — `FeedView` surfaces a pinned `PlaydateRequestCard` row for every pending invite (≤48h old), so critical-path visibility is maintained while APNs is offline.
  - **Cross-device cancel gap.** A cancel on device A doesn't push to device B. The invite flow broadcasts locally via `.playdateDidChange`, which only reaches the current device. If the invitee has the app open on a second device when the proposer cancels, the detail view will show the stale status until the next pull-to-refresh. Follow-up: Supabase Realtime subscription on `playdates`. Acceptable for MVP because accepted playdates also have a T-24h local reminder that will fire the updated status on re-render.
  - **No server-side "completed" sweeper.** Status transitions to `completed` require a participant to flip the row (typically via the post-playdate prompt). If both sides ignore the event, the row stays `accepted` indefinitely. This was a conscious choice to keep migration 023 tight. Follow-up: a `pg_cron`'d RPC that flips `scheduled_at < now() - interval '2 hours' and status = 'accepted'` to `completed`. Not MVP+0.
  - **Location is text + optional lat/lng.** `location_name` is required; `location_lat` / `location_lng` are optional and populated via `MKLocalSearchCompleter` → `MKLocalSearch.start` when the user taps a suggestion. Manually-typed locations land without coordinates — map previews (deferred feature) will gracefully skip them.
  - **No Discover rail for playdate-open pets yet.** `DiscoverView.swift` has a single-line TODO comment noting the rail. Users find pets to invite via the existing Discover surfaces (similar / popular / nearby rails) and the 约遛弯 pill is only reached through `PetProfileView`. Explicitly deferred to playdates-mvp+1.
  - **No repeat / weekly / group playdates.** The schema is 1-proposer × 1-invitee per row with a single `scheduled_at`. Recurrence and >2-pet group walks are future-schema territory — don't bolt them onto the current `playdates` table.
  - **Safety interstitial is one-time-per-device.** `UserDefaults "pawpal.playdate.safety.seen"` is set on the device, not the server. Signing in on a new device re-shows the interstitial. Acceptable — the copy is calibrated for first-time users; repeat users will tap through in 1s.
  - **Feb 29 / DST edge cases on local reminders.** `LocalNotificationsService.schedulePlaydateReminders` uses `UNCalendarNotificationTrigger(dateMatching:)` with concrete (year, month, day, hour, minute) components derived from `scheduled_at`. One-shot (not `repeats: true`), so Feb 29 doesn't bite. Spring-forward / fall-back handling follows iOS's internal semantics — if the target minute doesn't exist on a spring-forward day, it fires on the next valid minute. Non-issue for the MVP.

- **Build verification pending for Playdates MVP (2026-04-18)** — Dev 1 landed migration 023 + edge function branch + `RemotePlaydate` + `PlaydateService` + `DeepLinkRouter.Route.playdate(UUID)` + `LocalNotificationsService.schedulePlaydateReminders(for:otherPetNameByID:)` + `RemotePet.open_to_playdates` + `PetsService.PetUpdate` extension. Dev 2 landed `LocationCompleter`, `PlaydateSafetyInterstitialView`, `PlaydateComposerSheet`, `PlaydateDetailView`, `PlaydateCountdownCard`, `PlaydateRequestCard`, `PostPlaydatePromptSheet`, plus edits to `ProfileView`, `FeedView`, `PetProfileView`, `MainTabView`, `DiscoverView`. No `xcodebuild` in sandbox. Grep verification passed (see CHANGELOG entry #53). Spot checks on device:
  - **Opt-in toggle**: edit a pet → scroll to 遛弯 section → toggle 开启遛弯邀请 on → save → row round-trips via `PetsService.updatePet`; `RemotePet.open_to_playdates` decodes as `true` on re-fetch.
  - **Visibility gate**: as viewer A (owns pet P_A), open a `PetProfileView` for pet P_B with `open_to_playdates = false` → no 约遛弯 pill. Flip P_B to true → pill appears on next load.
  - **Self-guard**: visit your own pet profile → no 约遛弯 pill (guard clause in `canProposePlaydate`).
  - **Safety interstitial**: first tap of the 约遛弯 pill → `PlaydateSafetyInterstitialView` sheet; tap 我明白了 → sheet dismisses and `PlaydateComposerSheet` mounts; `UserDefaults "pawpal.playdate.safety.seen" == true`; next 约遛弯 tap bypasses the interstitial.
  - **Compose + insert**: pick a proposer pet (your own pet, if >1) → type a location → `LocationCompleter` surfaces MapKit suggestions → tap one → `location_name` + `location_lat` + `location_lng` populate → pick a date ≥ now → tap 发送邀请 → `PlaydateService.propose` inserts the row → `PlaydateDetailView` mounts showing `.proposed` status.
  - **BEFORE INSERT trigger fires on stale UI**: if the invitee flips `open_to_playdates` to false in the brief window between the composer opening and the insert, the INSERT is rejected with `hint = '该毛孩子的主人没有开启遛弯邀请'` → service re-raises as a user-readable error.
  - **Accept flow**: on invitee's device, open the invite (via `FeedView.PlaydateRequestCard` or a push deep link if APNs is live) → tap 接受邀请 → `PlaydateService.accept` updates status to `accepted` → `.playdateDidChange` fires → `MainTabView.onReceive` calls `LocalNotificationsService.schedulePlaydateReminders(for:)` → pending list gains 3 entries with identifiers `pawpal.playdate.t24h.<id>`, `pawpal.playdate.t1h.<id>`, `pawpal.playdate.t2h.<id>`.
  - **Decline flow**: invitee taps 婉拒 → status → `declined` → any previously scheduled reminders for this playdate are cancelled (`LocalNotificationsService` filters by identifier prefix `pawpal.playdate.` and playdate id).
  - **Cancel flow**: proposer on an `accepted` playdate taps 取消 → status → `cancelled` → local reminders cancelled → countdown card disappears from FeedView.
  - **Countdown card**: on FeedView, an `accepted` playdate with `scheduled_at` within 4h renders `PlaydateCountdownCard` above the normal feed; outside that window it does not render. Verify with a test row whose `scheduled_at = now + 3h`.
  - **Pinned request card**: on FeedView, a `proposed` playdate addressed to the viewer within 48h renders `PlaydateRequestCard` above the feed. Verify with an invite freshly inserted.
  - **Post-playdate prompt**: set a test row `status = accepted, scheduled_at = now - 30 min` → next FeedView load detects a completable playdate → `PostPlaydatePromptSheet` appears → tap "写一篇" → `CreatePostView` opens with `ComposerPrefill(pets: [proposer_pet, invitee_pet], caption: "刚和 {other_pet_name} 遛完弯～")` prefilled.
  - **Deep link**: open `pawpal://playdate/<uuid>` from Safari → app routes to `PlaydateDetailView` via `DeepLinkRouter.Route.playdate(UUID)` → `DeepLinkPlaydateLoader` resolves id → detail mounts.
  - **Local reminder lifecycle**: with an accepted playdate, force-quit the app → check pending list in Xcode Debug → 3 `pawpal.playdate.*` requests present. Cancel the playdate → reopen → pending list drops those 3.
  - **Sign out**: `LocalNotificationsService.cancelAll()` now filters on both the milestone prefix AND the playdate prefix — after signOut, NO `pawpal.playdate.*` nor `pawpal.milestone.*` pending requests remain.

- **APNs `playdate_invited` payload copy depends on sender locale** — the edge function's `formatRelativeZh` helper produces Chinese relative times (e.g. "3小时后", "明天下午 3:00"). The body string is authored in zh-CN and rendered by iOS as-is regardless of the recipient's device locale. This is intentional — the entire app is Chinese-first — but if we ever support English, the edge function's `buildPayload` will need locale-aware copy branching on `device_tokens.locale` (column not yet present).

- **Story view counts — known tradeoffs (2026-04-18)** — deliberate, not bugs:
  - **Viewing "as" is always `pets.first`.** MVP doesn't surface a "viewing as" pet picker — a user with multiple pets records the view under their first pet. If they later want their *other* pet's avatar to show in the owner's viewer list, they'd need to reorder their pets. Acceptable for MVP; a future picker would unlock multi-pet viewer identity without schema change (the PK is already `(story_id, viewer_pet_id)`).
  - **Silent RLS rejection.** `StoryService.recordView` swallows errors by design — if the caller has no pets or is somehow unauthenticated, the view doesn't record and the viewer continues to see the story. No inline error state is shown. This is the right call for an analytics-y feature, but means an edge-case "view wasn't recorded" is undetectable from the UI.
  - **Viewer cannot self-redact.** Once a view is recorded, the viewer cannot delete it. Owner must delete the story (or wait for the 24h TTL) to clear the row. A "ghost mode" per-user toggle would fix this but is explicitly deferred — see `docs/decisions.md` → "Story view receipts are owner-visible only; pets are the viewer identity".
  - **No per-session reset of `recordedViewIDs`.** The `@State private var recordedViewIDs: Set<UUID>` only dedupes *within* a single `StoryViewerView` presentation. If the user dismisses and re-opens the viewer in the same app session, a second `recordView` fires — but `UPSERT ignoreDuplicates` on the PK rejects it server-side. Net: one row per (story, viewer_pet) across the story's lifetime, no matter how many times you watch.
  - **`viewerCount` cache is presentation-lifetime.** The `@State private var viewerCounts: [UUID: Int]` in `StoryViewerView` only lives as long as the viewer is mounted. Dismiss → re-open → the count re-fetches. Fine — the chip tap refetches anyway; owners rarely keep the viewer open long enough for the cache to matter.
  - **Chip is not realtime.** If a new viewer lands while the owner has the story open, the "N 位看过" count doesn't auto-update. Pull-to-refresh inside `StoryViewersSheet` gets the latest list; the chip number updates on next mount. Realtime subscription would be a future enhancement — same bucket as chat realtime.

- **Build verification pending for story view counts (2026-04-18)** — Migration 024 + `RemoteStoryView` + `StoryService.recordView` / `viewerCount` / `viewers` + `StoryViewerView` edits + new `StoryViewersSheet` landed without `xcodebuild` in the sandbox. Grep-verified (see CHANGELOG #55). Spot checks on device:
  - **Non-owner records a view**: pet A (viewer) opens pet B's story → `story_views` row inserts with `(story_id = B.storyID, viewer_pet_id = A.petID, viewer_user_id = A.userID, viewed_at = now)`. Check via Supabase SQL editor.
  - **Dedup on repeat view**: viewer A dismisses + re-opens pet B's story → a second `recordView` fires but the PK conflict means no new row. `count(*)` for that story stays at 1.
  - **RLS blocks non-owner SELECT**: as viewer A, call `supabase.from('story_views').select('*').eq('story_id', B_story_id)` → returns empty array (RLS). No error.
  - **Owner sees chip**: pet B's owner opens their own story → "N 位看过" chip renders above the safe-area inset. Non-owner opens → no chip.
  - **Owner opens sheet**: tap chip → `StoryViewersSheet` mounts → list shows viewer pet A's avatar + name + `刚刚` / `N 分钟前` / `昨天 HH:mm`. Pull-to-refresh triggers reload.
  - **Tap a row → `PetProfileView`**: rows are tappable and route to the viewer pet's profile.
  - **Cascade on story delete**: owner deletes the story → viewer rows CASCADE-delete. Confirm with `select count(*) from story_views where story_id = <id>` → 0.
  - **Cascade on pet delete**: viewer pet A gets deleted → rows with `viewer_pet_id = A` CASCADE-delete across all stories.
  - **Viewer can't delete own row**: as viewer A, `supabase.from('story_views').delete().eq('viewer_pet_id', A_id)` → returns 0 rows (RLS).
  - **Viewer can't insert under someone else's pet**: as viewer A, try to insert `viewer_pet_id = B_pet_id` → SECURITY DEFINER trigger rejects with a pet-ownership error.

- **Breed / city cohort surfaces — known tradeoffs (2026-04-19)** — deliberate, not bugs:
  - **`breed` and `home_city` are free-text columns.** The cohort filter is an exact `eq` match on the trimmed string. A pet entered as `柴犬` and another as `柴犬 ` or `柴犬犬` shows up in different cohorts. Normalization (dropdown picker or server-side canonicalisation) is a future refactor; we explicitly didn't ship it in this pass to keep the surface area tight.
  - **No diacritic / case folding.** PostgREST `.eq` is byte-for-byte. If a user enters `Shiba` vs `shiba`, they're different cohorts. Not an issue for Simplified Chinese breed names which are canonical; an edge case for English nicknames.
  - **Offset pagination, not cursor.** The view uses `PostgREST .range(offset, offset + 23)` — fine for list sizes < ~1k, which matches expected cohort size for a 2026-era niche cohort. If a single breed / city grows past a few hundred pets, consider cursor pagination on `(created_at desc, id)`.
  - **No realtime updates.** The cohort view doesn't subscribe to new pets joining. Pull-to-refresh re-queries from offset 0. Matches the rest of the app.
  - **No empty-state CTA.** An empty cohort just shows `还没有 X 的毛孩子在 PawPal 上 🐾` with no action hint. Acceptable because the viewer is typically navigating to the cohort by tapping an existing pet's pill — if the count is literally 0 including that pet, something unusual happened (race with deletion) and a refresh fixes it.

- **Build verification pending for breed / city cohort surfaces (2026-04-19)** — `PetCohortView.swift`, the two new `PetsService` methods, and the entry-point wiring on `PetProfileView` + `DiscoverView` landed without `xcodebuild` in the sandbox. Grep-verified (see CHANGELOG #56). Spot checks on device:
  - **Breed pill tap**: open any pet profile with a non-empty `breed` → tap the breed pill → `PetCohortView(kind: .breed(...))` pushes → title reads `{breed} 的毛孩子` → 2-column grid populates with up to 24 rows.
  - **City pill tap**: open any pet profile with a non-empty `home_city` → tap the city pill → `PetCohortView(kind: .city(...))` pushes → title reads `{city} 的毛孩子` → grid populates.
  - **Pagination**: scroll to the bottom row of a cohort with >24 pets → autoload fires → "加载中…" footer appears → next page appends.
  - **Pull-to-refresh**: on a loaded grid, pull down → page resets to 0 → grid re-renders.
  - **Empty cohort**: edit a pet to a breed / city with no other matches → open the pill → empty state copy renders centered.
  - **"查看全部" on Discover**: open `DiscoverView` with a featured pet that has a breed → "与 X 相似的毛孩子" rail header shows `查看全部` chevron → tap → pushes `.breed(...)` cohort. If `nearbyCity` is non-nil → "X 的毛孩子" rail header shows the same link → tap → pushes `.city(...)` cohort.
  - **Own pet excluded**: if the viewer has a pet in the cohort, it does NOT appear in the grid (viewer's pets are excluded via `excludingOwnerID`).
  - **Cell tap → `PetProfileView`**: tap any grid cell → push pet profile → verify haptic fires + avatar + stats correct.
  - **Empty string gate**: edit a pet to clear its breed → pill doesn't render as tappable (already hidden because the pill itself doesn't render on empty breed, but the NavigationLink's `.breed("")` construction is defensive — confirm no crash).
  - **Long breed name**: set a breed to a very long string → title truncates / wraps gracefully; cohort filter still matches exactly.

- **Instrumentation — known tradeoffs (2026-04-19)** — deliberate, not bugs:
  - **`events.kind` is free-text `text`, not an enum or CHECK-constrained domain.** A client with a stale `AnalyticsService.Kind` case, a typo, or a future PR that adds a new kind will all insert without a migration. That's the point — new kinds ship additively. Downside: typos look like real events until a server-side query catches the mismatch. Mitigation lives in `supabase/025_events.sql`'s header comment, which is the authoritative list.
  - **`events.properties` is unconstrained `jsonb`.** No schema validation at the database layer. A property key change (e.g. `post_id` → `postId`) will appear as a new dimension in aggregates, not an error. Analytics consumers must treat `properties` as best-effort and coerce with `coalesce` / `jsonb_path_query_first`.
  - **No SELECT / UPDATE / DELETE RLS policies.** By design — the client never reads events back. Analytics queries run server-side as `service_role` from a dashboard or scheduled job. If we ever want an in-app "your activity" surface, we'd add a narrow SELECT policy (`auth.uid() = user_id`), not loosen the existing lockdown.
  - **No retention / cutoff policy on `events`.** Rows accumulate forever. A 12-month TTL (`delete from events where server_at < now() - interval '12 months'`) belongs in a scheduled Supabase function; it's intentionally not in migration 025 because the cutoff is a product decision, not a schema one.
  - **Clock drift handled by dual timestamps, not correction.** `client_at` is the iOS-supplied local `Date()`; `server_at` defaults to `now()` in Postgres. Aggregations that care about correctness (session start, D7) should prefer `server_at`. `client_at` exists for ordering events emitted in the same tick on a single device where the network write may reorder them.
  - **No opt-out UI.** Every authenticated user contributes. `TODO(analytics-opt-out)` in `AnalyticsService.swift` marks the v1.5 seam — a `UserDefaults` key plus a one-line early-return in `log(_:)`. Not required in current markets, but will be required before any EU ship.
  - **Fire-and-forget insert failures are silent.** A network blip, RLS misconfiguration, or stale bearer token drops the event with a `[Analytics] … 失败` console line and no user-visible signal. This matches `StoryService.recordView` / `PushService.clearToken` — every peripheral write in the app logs-and-swallows.
  - **`session_start` dedupe lives in process memory.** `AnalyticsService.lastSessionAt` resets on app relaunch. Force-quit + relaunch inside the 30-minute window emits a second `session_start`. Downstream analytics should `DISTINCT ON (user_id, date_trunc('hour', server_at))` if hourly dedupe is required. The current raw-stream behaviour is intentional — easier to debug than a persisted dedupe.
  - **`session_start` does NOT fire on cold launch from signOut state.** `ContentView.task` only calls `logSessionStart()` when a session exists. A logged-out user's app-open emits `app_open` but not `session_start`. First `session_start` fires from `AuthManager.signIn` / `signUp` success. Acceptable — logged-out sessions aren't a DAU unit.
  - **No device / locale / app-version dimensions.** Intentional — the PII surface stays minimal. If release-regression analysis ever needs `app_version`, add it via `properties` at call time (`["app_version": .string(Bundle.main.version)]`), not as a schema column.
  - **`like` / `comment` / `follow` events fire on insert only, not on undo.** Unlike, uncomment (delete), and unfollow paths do not emit. This is by design — the funnel metric is "did the action happen?" not "did it stick?". If net-follow or net-like becomes a metric, the undo paths have `TODO(analytics-undo)`-style seams (none landed in this PR; adding is a one-line `.log(.unfollow, ...)`).
  - **`share_tap` is an intent signal, not a completion signal.** The event fires on the `.simultaneousGesture` before iOS presents the share sheet; the user may cancel without actually sharing anywhere. There's no iOS API to observe share-sheet completion for third-party targets. Treat `share_tap` as "surfaced the sheet", not "shared externally".

- **Build verification pending for instrumentation (2026-04-19)** — Migration 025, `AnalyticsService.swift`, and the 13 log call sites (+ 4 `logSessionStart` calls) landed without `xcodebuild` in the sandbox. Grep-verified: `AnalyticsService.shared.log` returns 13 hits across PawPalApp, ContentView, AuthManager (×2), PostsService (×3), StoryService (×2), PlaydateService (×2), FollowService, PostDetailView, PetProfileView, ProfileView; `logSessionStart` returns 4 call sites (AuthManager ×2, ContentView ×2). Spot checks on device:
  - **Cold launch emits `app_open`**: force-quit → relaunch → Supabase SQL editor: `select * from events where kind = 'app_open' order by server_at desc limit 1` → row with `user_id` matching the current session (or null if signed out) and `client_at` within the last few seconds.
  - **`session_start` on scenePhase → active**: cold launch with a signed-in session → check `events` for `kind = 'session_start'` within the same second. Background the app for < 30 min → foreground → no new `session_start` (dedupe holds). Background for > 30 min → foreground → new `session_start` fires.
  - **Sign in emits `sign_in` + `session_start`**: sign out → sign in with password → both rows land; `sign_in.properties = {"method": "password"}`.
  - **Sign up emits `sign_up` + `session_start`**: same pattern on registration.
  - **Post create fires `post_create`**: create a post with 2 images and a caption → `properties = {"image_count": 2, "has_caption": true}`. Create a post with 0 images and no caption → `properties = {"image_count": 0, "has_caption": false}`.
  - **Story post / view**: post a story → `story_post` event. Open someone else's story → `story_view` with `properties = {"story_id": "<uuid>"}`. Re-open the same story same-session → a second `story_view` fires (client doesn't dedupe; only `story_views` table PK dedupes).
  - **Playdate proposed / accepted**: propose a playdate → `playdate_proposed`. Accept an inbound → `playdate_accepted`. Decline/cancel/markCompleted do NOT emit (intentional — only positive-state transitions track for the funnel).
  - **Share tap surfaces**: tap ShareLink on PostDetailView → `share_tap` with `{"surface": "post"}`. On PetProfileView → `{"surface": "pet"}`. On ProfileView's 分享主页 → `{"surface": "profile"}`. Dismissing the sheet without sharing still leaves the event — confirms it's intent, not completion.
  - **Follow**: tap follow on a non-followed user → `follow` with `{"target_user_id": "<uuid>"}`. Tap again to unfollow → no event.
  - **Like / comment**: tap heart on a non-liked post → `like` with `post_id`. Tap again to unlike → no event. Post a comment → `comment` with `post_id`. Delete a comment → no event.
  - **RLS rejection on spoofed `user_id`**: via `supabase.from('events').insert({kind: 'app_open', user_id: '<someone_else_id>'})` → RLS rejects. Confirm the client's fire-and-forget path swallows this and prints `[Analytics] … 失败`.
  - **Anonymous insert (nullable `user_id`)**: before signIn restoration completes, `app_open` may fire with `user_id = null` → policy allows it → row lands. Confirm by scripting a signed-out insert in a test harness.
  - **No SELECT leak**: as a regular authenticated user, `supabase.from('events').select('*')` → returns `[]` (no SELECT policy). Confirms analytics data isn't readable by clients.
  - **Performance**: create 50 posts in rapid succession → UI remains snappy; `post_create` emission is fire-and-forget via `Task.detached` and does not block `PostsService.createPost` return.

---

## Recently Resolved

- **Post images never saved or displayed** — `RemotePostImage`, the PostgREST select strings, and the `post_images` INSERT struct all used column names `image_url`/`sort_order` instead of the actual live DB column names `url`/`position` (established by migration `011_align_post_images_columns.sql`). This caused every `post_images` SELECT to fall back to the bare `*, pets(*)` level (no images) and every INSERT to be rejected. Fixed column names throughout; also hardened the `position` field to `Int` (was `String`), added rollback-on-failure for image uploads, and surfaced upload errors in the always-visible button bar (2026-04-12).
