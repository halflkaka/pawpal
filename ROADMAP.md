# PawPal Roadmap

## Current State

Phases 1, 2, and 3 are complete; Phase 3 was reshaped in #48 (Discover replaces Contacts). Phase 4 is partial (pet-specific follow remains). Phase 4.5 (ephemeral stories) now covers view counts / seen-by (2026-04-18) on top of the image-only MVP — video stories remain deferred. Phase 5 (Messaging) shipped its DM MVP in #45, added entry points in #46, and picked up compose-new in #47. Phase 6 has landed a dense April 2026 sprint: onboarding gate (#47), passive virtual-pet decay (#48), pet milestones MVP (2026-04-18), push notifications v1 (2026-04-18), local-notifications stopgap (2026-04-18), **Playdates MVP (2026-04-18)**, **external share-out (2026-04-18)**, **breed/city cohort surfaces (2026-04-19)**, and **Instrumentation (2026-04-19)**. Feed algorithm and App Store prep remain.

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

- ✅ Pet-first `DiscoverView` (PR #48) — three rails (与 [pet] 相似的毛孩子 / 人气毛孩子 / [city] 的毛孩子), backed by new `PetsService.fetchSimilarPets`, `fetchPopularPets`, `fetchNearbyPets`. Replaces the legacy `ContactsView`. Empty-state CTA routes no-pet users to Me.
- Search works client-side across pet name, species, breed, city
- Trending topics derived dynamically from real post data (legacy — preserved as heuristic in Popular rail via `boop_count`)
- Pet-first explore tab — browse all pets by species, tap to open pet profile (PR #7)

## Phase 4 — Pet Profiles as First-Class Pages ⚠️ Partial

- Pet management (add, edit, delete) is fully real in `ProfileView`
- ✅ Dedicated pet profile page (`PetProfileView`) — navigable from profile, shows bio, tag pills, city, stats, post grid
- ✅ Pet avatar upload — `AvatarService` compresses and uploads to Supabase Storage; `PetsService.addPet` / `updatePet` accept `avatarData` and persist `avatar_url`
- ✅ Avatar upload in editor — `ProfilePetEditorSheet` supports photo picker and passes `avatarData` through
- ✅ Avatar photo display in `PetProfileView` — `AsyncImage` loads from `pet.avatar_url`; falls back to species emoji on nil or load failure
- ✅ User avatar upload — `AvatarService.uploadUserAvatar`; displayed in `profileHeader` via `AsyncImage`; `PhotosPicker` in `ProfileAccountEditorSheet` (PR #12)
- ✅ Pet-first Me profile (PR #47) — `profileHeader` leads with `petHeroRow(_:)` (72pt pet avatar + name + species/breed/city pills); owner @handle demoted to a secondary line. Empty state swaps to `addFirstPetHeroCard` CTA.
- ✅ Featured-pet badge on user-list surfaces (PR #47) — FollowListView rows, ChatListView threadRow, and the compose-new sheet all overlay the owner's first pet on top of the user avatar via `PetsService.loadFeaturedPets`.
- 🔲 Pet-specific follow (follow a pet, not just a user) — current follow graph is user-to-user only

## Phase 4.5 — Ephemeral Stories ⚠️ MVP (images only; video deferred)

- ✅ `stories` schema (PR #48) — migration 018 introduces the table + RLS (SELECT gated on `expires_at > now()`, INSERT gated on pet ownership, DELETE owner-only). `story-media` Supabase Storage bucket is provisioned manually.
- ✅ `StoryService.shared` — loads active stories (grouped by pet), posts a story (upload → insert → optimistic cache fold), deletes owner's stories, O(1) `hasActiveStory(for:)` lookup.
- ✅ `StoryComposerView` + `StoryViewerView` — pet-first composer, Instagram-style tap-through viewer with progress bars, long-press pause, swipe-down dismiss.
- ✅ Home rail wired to stories — own pet with no story opens composer, own pet with story opens viewer, friend pets without active stories fall out of the rail.
- ✅ "Seen by" / view counts (2026-04-18) — migration 024 adds `story_views` (composite PK `(story_id, viewer_pet_id)`, denormalised `viewer_user_id`, `ON DELETE CASCADE` on both FKs) with owner-only SELECT/DELETE RLS and a SECURITY DEFINER BEFORE INSERT trigger for the pet-ownership gate. `StoryService.recordView` / `viewerCount` / `viewers`; `RemoteStoryView` model; owner-only "N 位看过" chip on `StoryViewerView` opens `StoryViewersSheet` (pet-first row list, pull-to-refresh, tap → `PetProfileView`). Non-owners silently record one receipt per story per session (viewing-as-pet = `pets.first`).
- 🔲 Video stories — schema accepts `media_type = 'video'`; client is image-only for now (`TODO(video)` seams in composer + viewer)

## Phase 5 — Messaging ⚠️ Mostly complete (text DMs + entry points landed)

- ✅ `ChatListView` redesigned — serif wordmark, cream search, online rail with DogAvatar bubbles, threaded rows with unread badges (April 2026 refresh)
- ✅ `ChatDetailView` new — sticky header, bubble groups with reaction overlay, "typing…" indicator, sticker tray, composer with accent send button
- ✅ Real backend (PR #45) — `conversations` + `messages` tables via migration 017, `ChatService.shared` with canonical participant ordering, optimistic send + rollback, partner profile hydration in a single batched call
- ✅ Chat entry points (PR #46) — 给主人发消息 pill on PetProfileView, 发消息 shortcut on FollowListView rows
- ✅ Compose-new sheet (PR #47) — `+` in ChatListView opens a sheet listing the viewer's following and routes tap → `ChatDetailView` via `ChatService.startConversation`
- 🔲 Realtime subscriptions (typing indicators, online dots, sticker tray, per-message reactions) — intentionally deferred per `docs/scope.md`
- 🔲 Read receipts / unread tracking — needs `last_read_at` on `conversation_participants`

## Phase 6 — Retention & Growth ⚠️ Partial

Direction reset on 2026-04-18 (see `docs/sessions/2026-04-18-pm-direction-playdates.md`). Pet care / health logging dropped; playdates promoted as the flagship pet-to-pet feature; milestones + push are foundations for it.

- ✅ Onboarding flow for new users (PR #47) — `OnboardingView` full-screen gate forces first-pet creation before the tab bar renders
- ✅ Passive virtual-pet decay (PR #48) — `VirtualPetStateStore.decayedState` applies hunger -3/hr, energy +2/hr, mood -1/hr on read; `applyAction` computes the decayed baseline first so taps stack on top of the drifted value.
- ✅ Pet milestones MVP (2026-04-18) — birthday card + memory loop card on FeedView, "即将到来的纪念日" rail on PetProfileView, composer prefill API on CreatePostView. Birthday derived from `pets.birthday` (column has existed since 001 but `RemotePet` was missing the field — fixed in this pass). Memory loop backed by new `PostsService.loadMemoryPosts(forUser:)`. Stateless `MilestonesService` per the "derived not stored" decision (`docs/decisions.md`).
- ✅ Push notifications v1 (2026-04-18) — `device_tokens` + `notifications` tables via migration 022; AFTER INSERT triggers on `likes`, `comments`, `follows` queue a row and fire `pg_net.http_post` at the `dispatch-notification` edge function (Deno, ES256 APNs JWT, direct APNs — no FCM). iOS: new `PushService`, `AppDelegate`, `DeepLinkRouter`; priming sheet after onboarding; token register/clear wired into `AuthManager.signIn/register/restoreSession/signOut`; `pawpal://` URL scheme + `onOpenURL` routing. v1.5 (milestone day-of, playdate reminders, chat DM pushes) reuses the same pipeline. Direction doc: `docs/sessions/2026-04-18-pm-push-notifications.md`. Note: APNs delivery gated on user-owned Apple Developer Program enrollment — code is live; on-device delivery activates once prerequisites land (see `docs/known-issues.md`).
- ✅ Local notifications stopgap (2026-04-18) — device-scheduled birthday day-of reminders via `UNCalendarNotificationTrigger` (fires 09:00 local on pet's month-day, repeats yearly). No APNs key required. New `LocalNotificationsService` singleton; rescheduled in `MainTabView` on pets cache change + scenePhase → active; cancelled on signOut. Routes tap → `.pet(UUID)` → `PetProfileView`. Coexists with APNs — local owns device-schedulable milestones, APNs owns server-originating events. Direction doc: `docs/sessions/2026-04-18-pm-local-notifications-stopgap.md`.
- ✅ Playdates MVP (2026-04-18) — schedule + accept/decline + cancel + post-playdate prompt shipped. Migration 023 introduces `pets.open_to_playdates` (opt-in, default false) and a new `playdates` table (proposer/invitee pet ids + denormalised user ids + scheduled_at + location + status enum proposed/accepted/declined/cancelled/completed), airtight RLS, a BEFORE INSERT trigger enforcing the open-to-playdates gate, and an AFTER INSERT notify trigger that reuses migration 022's `queue_notification` with type `playdate_invited`. Edge function `dispatch-notification` adds a `playdate_invited` branch (Chinese title/body with relative time via `formatRelativeZh`). iOS: new `PlaydateService.shared` (fetch inbox/outbox/details, propose with optimistic insert + RLS-error bubbling, accept/decline/cancel/markCompleted, `.playdateDidChange` broadcast); new `RemotePlaydate` model with `Status` enum; `DeepLinkRouter.Route.playdate(UUID)` case (routes `playdate_invited` + `pawpal://playdate/<uuid>`); `LocalNotificationsService.schedulePlaydateReminders(for:otherPetNameByID:)` schedules three `UNCalendarNotificationTrigger` reminders per accepted playdate (T-24h, T-1h, T+2h with identifiers `pawpal.playdate.t<n>.<uuid>`), cancelled on decline/cancel/complete; `MainTabView` observes `.playdateDidChange` and reschedules. UI: 约遛弯 pill on `PetProfileView` (gated on viewer owns a pet + target pet is open + not self), `PlaydateSafetyInterstitialView` (one-time seen gate via `UserDefaults "pawpal.playdate.safety.seen"`), `PlaydateComposerSheet` (pet picker + location autocomplete via `MKLocalSearchCompleter` → `LocationCompleter` + scheduled_at + optional message), `PlaydateDetailView` (status-aware Accept/Decline/Cancel buttons + countdown), pinned `PlaydateRequestCard` + `PlaydateCountdownCard` rows on `FeedView` (48h unanswered invites + 4h upcoming accepted), `PostPlaydatePromptSheet` firing post-completion to prefill `CreatePostView` via extended `ComposerPrefill(pets:)`. `ProfileView.ProfilePetEditorSheet` gets an 开启遛弯邀请 toggle; `RemotePet.open_to_playdates` round-trips codable with a defensive default; `PetsService.updatePet` accepts the new field through `PetUpdate`.
- ✅ Breed / city cohort surfaces (2026-04-19) — new `PetCohortView` renders a paginated list (24-row pages, `created_at desc`, pull-to-refresh, two-column grid) of every pet in a breed or city cohort via a single `Kind` enum. Backed by new `PetsService.fetchPetsByBreed(_:excludingOwnerID:limit:offset:)` and `fetchPetsByCity(_:excludingOwnerID:limit:offset:)` (trimmed case-sensitive `.eq` + inclusive `.range`). Entry points: tappable breed + city pills on `PetProfileView` (chevron hint + `.light` haptic) push via `.navigationDestination(for: PetCohortView.Kind.self)`; `DiscoverView` rails gain a "查看全部" header link — breed-first on the "与 X 相似的毛孩子" rail (falls through when the featured pet has no breed), city on the "X 的毛孩子" rail. No schema change; the existing `fetchSimilarPets` / `fetchPopularPets` / `fetchNearbyPets` rail methods remain untouched.
- ✅ External share out (微信 / 朋友圈 / 小红书) (2026-04-18) — `ShareLinkBuilder` centralises `pawpal://post/<uuid>`, `pawpal://pet/<uuid>`, `pawpal://u/<slug>` URLs + Chinese share messages. `ShareLink` affordances landed in `PostDetailView` (`.topBarTrailing` toolbar), `PetProfileView` (toolbar), and `ProfileView` (existing 分享主页 chip now routes through the builder). `DeepLinkRouter` accepts `pawpal://u/` as an alias for `profile` (uuid round-trips today, handle→user resolution is a follow-up — the URL is still a valid share artefact either way). Universal links / associated domains deferred to the App Store prep phase.
- ✅ Instrumentation (D7, posts/DAU, sessions/week) (2026-04-19) — first-party event log only (no Firebase / Mixpanel / Amplitude / Segment / any third-party analytics SDK). Migration 025 adds `public.events` (uuid id, nullable `user_id` FK → profiles, `kind text`, `properties jsonb`, `client_at` + `server_at` timestamps) with airtight INSERT RLS (`user_id is null OR auth.uid() = user_id`) and **no SELECT policy** — analytics runs server-side as `service_role` only. iOS: new `AnalyticsService.shared` singleton (`@MainActor final class`) with `log(_:properties:)` fire-and-forget API — every call dispatches a detached `Task`, reads the session id off the shared Supabase client, and swallows insert failures with a `[Analytics] … 失败` console line; `logSessionStart()` client-side-debounces `session_start` emission to at most one per 30 minutes via a private `lastSessionAt: Date?`. Thirteen event kinds wired in this PR (all additive — new kinds do NOT require a schema migration): `app_open` (App struct init), `session_start` (scenePhase → active + signIn + signUp), `sign_in`/`sign_up` (AuthManager success paths, `method = "password"`), `post_create` (PostsService success, `image_count` + `has_caption`), `story_post` + `story_view` (StoryService, `story_id` for view), `playdate_proposed` + `playdate_accepted` (PlaydateService success paths), `share_tap` (ShareLink `.simultaneousGesture` on post/pet/profile — `surface` dim), `follow` (FollowService success, `target_user_id` dim), `like` + `comment` (PostsService success paths — insert only, NOT on unlike / delete, `post_id` dim). No PII beyond `user_id` + dimensional metadata; no device id, no advertising id, no IP, no precise location, no user-authored text (captions/comments/chat bodies). `TODO(analytics-opt-out)` seam reserved for a v1.5 opt-out UI + iOS ATT-style prompt. Decisions: `docs/decisions.md` → "First-party event log; no third-party analytics SDK".
- 🔲 Feed algorithm (recency + social graph weighting)
- 🔲 App Store assets, privacy policy, TestFlight beta
