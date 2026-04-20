# Decision Log

Architectural, product, and design-philosophy decisions worth preserving. These explain *why* the app is built the way it is — so future developers and AI agents don't accidentally undo deliberate choices.

Each entry: what was decided, why, and what it means going forward.

---

## Supabase is the single source of truth

**Decision:** All data is fetched from and written to Supabase. SwiftData local caching was removed.

**Why:** Local caching added complexity (sync conflicts, stale state, cache invalidation) without meaningful benefit for an app that assumes an active internet connection. Supabase handles persistence, auth, and storage — a single layer is simpler to reason about and debug.

**Implications:** Do not reintroduce SwiftData or local caching. `SwiftDataModels.swift` exists but is intentionally empty. Offline support is not a current goal.

---

## Social graph is user-to-user, not pet-to-pet

**Decision:** Follow relationships are between user accounts (`follower_user_id → followed_user_id`), not between pet profiles.

**Why:** Keeps feed queries simple. A user-to-user graph means one join to get a feed; pet-to-pet would require resolving pet ownership before filtering posts. Most users own one pet anyway.

**Implications:** Do not add pet-level follow without revisiting feed query design. Phase 4 explores pet-specific follow — that is a deliberate future decision, not an oversight.

---

## Profiles are lightweight; pets are the social actors

**Decision:** `profiles` holds only account-level identity (username, display name, avatar). `pets` holds the rich social identity (species, breed, bio, home city, personality).

**Why:** The app is pet-first. The human account exists for login, ownership, and trust. Pets are the visible, expressive presence in the feed. Keeping profiles lean makes it easier to evolve pet profiles independently.

**Implications:** When adding social features, default to putting attributes on pets, not profiles. Email stays in Supabase auth and is never duplicated in `profiles`.

---

## Chinese-first UI

**Decision:** All user-facing text in the app is written in Chinese (Simplified).

**Why:** The primary target audience is Chinese-speaking users.

**Implications:** All new UI strings should be in Chinese. Do not add English-language UI text without explicit instruction.

---

## Shared Supabase client across services

**Decision:** All services use `SupabaseConfig.client` — a single shared `SupabaseClient` instance — rather than each service instantiating its own.

**Why:** A shared client ensures all services operate on the same authenticated session and RLS context. Multiple clients caused inconsistent auth state across services.

**Implications:** Always use `SupabaseConfig.client` in new services. Do not instantiate `SupabaseClient` directly inside a service.

---

## Posts are preserved when a pet is deleted

**Decision:** `posts.pet_id` uses `ON DELETE SET NULL` rather than `ON DELETE CASCADE`.

**Why:** A user's post history should survive even if they remove a pet profile. Deleting a pet is not the same as deleting the memories associated with it.

**Implications:** The app must handle `post.pet_id == nil` gracefully in all views. Do not assume a post always has an associated pet.

---

## Feed is chronological, not algorithmic

**Decision:** The home feed is ordered by `created_at DESC`. No ranking, weighting, or personalisation logic.

**Why:** Algorithmic feeds require engagement signals, infrastructure, and tuning. The app is too early for this. Chronological is simple, predictable, and fair to all users.

**Implications:** Do not add ranking or scoring to feed queries. This is explicitly deferred to Phase 6 in `ROADMAP.md`.

---

## MapKit for city autocomplete in pet editor

**Decision:** The pet editor's home city field uses `MKLocalSearchCompleter` (MapKit) rather than a plain `TextField`.

**Why:** Free-text city entry produced inconsistent values (different spellings, missing regions) that are hard to display or query against. `MKLocalSearchCompleter` returns structured, real-world place names that are consistent and user-friendly to select.

**Implications:** `MapKit` is now a dependency of `ProfileView.swift`. The `LocationCompleter` class and `LocationPickerSheet` view live at the bottom of that file. Do not duplicate location search logic elsewhere — extract to a shared file if needed in more places.

---

## 2026 "warm serif + polaroid" visual refresh

**Decision:** The app's visual language was refactored against a new design prototype (`_standalone_.html` / `design_extract/`). The refactor touches every primary screen — Feed, Profile, Virtual Pet, Tab bar, Chat — plus the shared `PawPalDesignSystem.swift` palette. Chat was pulled forward from Phase 5 at the user's explicit request even though `docs/scope.md` had deferred it.

**Why:** The previous palette was a bright, saturated orange on pure white that read as generic; the new direction is a warm cream (`#FAF6F0`) background, a single warm-orange accent (`#FF7A52`), serif ("Fraunces" → `.serif` fallback) for wordmarks and pet names, and polaroid-style post cards with alternating tilt. The result is more magazine/journal than social-network. Pet-first identity is reinforced with vector `DogAvatar` fallbacks for every breed, and a playful `VirtualPetView` stage on dog profiles.

**Implications:**
- `PawPalDesignSystem.swift` is the authoritative palette. New screens must use its tokens (`PawPalTheme.accent`, `PawPalTheme.cardSoft`, `PawPalTheme.hairline`, `PawPalTheme.online`, etc.) rather than hardcoding colours.
- Old token names (`PawPalTheme.orange`, `.orangeSoft`, `.orangeGlow`) are kept as backward-compat aliases so ancillary files keep compiling. Do not resurrect these names in new code — prefer `accent` / `accentSoft` / `accentGlow`.
- `DogAvatar` is the breed-aware vector fallback used everywhere a pet photo might be missing. The chain is: real photo → `DogAvatar` (for dogs) → species SF Symbol → emoji. `PetCharacterView` is still rendered for non-dog species so we don't regress cats/rabbits/birds.
- `VirtualPetView` replaces `PetCharacterView` for dogs on the profile. It's decorative only — hunger/energy are derived from `PetStats` heuristically (no backend persistence).
- `ChatListView` + new `ChatDetailView` are local-only (no backend). Do not treat the sample data as production-ready; real chat requires a Supabase messaging table + realtime subscription, which is still in Phase 5.
- The Chinese-first UI rule is unchanged — all strings introduced by the refactor are in Simplified Chinese.

---

## Stories are their own table, not an extension of `posts`

**Decision:** The 24-hour ephemeral stories surface (PR #48, migration 018) lives in a dedicated `public.stories` table with its own RLS, indexes, and service layer (`StoryService`). It is **not** a boolean flag or new column on `posts`.

**Why:** Stories and posts differ in every meaningful dimension — lifetime (ephemeral vs permanent), ownership key (per-pet vs per-user), UX surface (fullscreen viewer vs feed card), read-path filter (`expires_at > now()` vs chronological), engagement model (no likes / comments / boops in the MVP vs the whole post interaction stack). Bolting those behaviours onto `posts` would have meant conditional columns, conditional RLS, and a feed query that constantly has to subtract expired rows. A separate table lets each model stay clean and lets us iterate on stories (seen-by, video, view counts) without risking the feed.

**Implications:** Keep the two models separate. A story is **not** a post; do not add a foreign key from `stories` back to `posts`, and do not expose stories in the feed query. When we add "seen by" later, it lands as a new `story_views` table — not on `posts`. The pet-first framing is reinforced: stories are keyed by `pet_id`, not `owner_user_id` (owner is a secondary column used for the INSERT ownership check).

---

## Direct APNs, no FCM — Chinese iOS reliability

**Decision:** Push notifications dispatch directly from a Supabase Edge Function to APNs. No FCM, no third-party push aggregator. Triggers on `likes`, `comments`, `follows` write a row to a `notifications` table and invoke the edge function via `pg_net.http_post`; the edge function signs an ES256 APNs JWT with the Apple `.p8` key and POSTs to `api.push.apple.com` (or `api.sandbox.push.apple.com` per the token's `env` column).

**Why:**
- **Mainland China reliability.** Apple operates APNs edge POPs inside China; FCM is blocked. Direct APNs is the only path that works for 中国大陆 iOS users at all, let alone reliably.
- **Fewer moving parts.** No third-party service to provision, no extra secret to rotate, no vendor-specific SDK in the iOS binary.
- **`pg_net` over Database Webhooks.** `net.http_post` is built into Supabase Postgres, fires inline with the trigger, has no external webhook config UI to drift out of sync with SQL, and is strictly lighter than a dedicated queue. Retries live inside the edge function (one 1s retry on 429/5xx).
- **`notifications` table, not fire-and-forget.** A persisted row gives us retryability (if APNs is down, we can replay), auditability ("did we push user X for event Y?"), and a future in-app notification center without a second data model.

**Implications:**
- Any new push type adds a value to the `notifications.type` CHECK (migration 022) and a branch in `dispatch-notification/index.ts`'s `buildPayload`. No new plumbing per type.
- The APNs `.p8` key, Key ID, Team ID, bundle ID, and env live in Supabase function secrets (`APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_ENV`). Never in the repo, never in the iOS binary.
- Token environment (`sandbox` / `production`) is per-token, stored on the `device_tokens` row, because a single user can have both a debug build and a TestFlight build on two devices. The edge function picks the APNs host per-token, not globally.
- Do not reintroduce FCM or any third-party push layer without revisiting Chinese delivery reliability.

---

## Milestones are derived, not stored

**Decision:** Pet milestones (birthdays, memory loops) are computed at render time from existing columns — `pets.birthday` and `posts.created_at`. There is no `milestones` table, no cron, no server-side job. `MilestonesService` is a stateless `@MainActor final class` with no cache, no `ObservableObject` state, no Supabase client (for the derivation methods themselves; `PostsService.loadMemoryPosts` does the one needed fetch).

**Why:** Every milestone the v1 surface ships is a pure function of data the app already stores. A dedicated table would add write paths (who records a birthday? what about backfill?), read paths (yet another SELECT in FeedView's already-long load chain), and RLS surface area — with zero user-facing benefit, because the derived answer is always correct. Separating "the source of truth" (`pets.birthday`, `posts.created_at`) from "the presentation" (milestones) is the same philosophy already applied to virtual-pet decay in `VirtualPetStateStore.decayedState` — compute on read, persist the source.

**Implications:**
- Do not add a `milestones` table. Do not add `milestone_views` (seen-by) without first ensuring the surface is durable enough to warrant it.
- New milestone kinds are added as cases on `MilestonesService.MilestoneKind` with a corresponding derivation function. They do not get schema columns.
- `pets.birthday` stays the canonical birthday; the Supabase schema in `001_schema.sql` line 23 is correct. The April 2026 gap was in the Swift model (`RemotePet` omitted the field), not the DB.
- All milestone copy is authored in Simplified Chinese inside `MilestonesService` (the derivation layer), not stringified at the view layer. Keeps copy centralised.
- Memory-loop scaling: `PostsService.loadMemoryPosts(forUser:)` filters client-side over up to 200 of a user's recent posts. If users start producing >200 posts/year, promote to a server-side RPC (search `TODO(milestones-mvp)` for the seam).

---

## Local notifications own device-schedulable events; APNs owns server events

**Decision:** Milestone day-of reminders (starting with birthdays in v1) are delivered via `UNCalendarNotificationTrigger` scheduled on-device, **not** via APNs. Social signals (like, comment, follow), chat DMs, and playdate T-minus reminders stay on the APNs path (migration 022 + `dispatch-notification` edge function). Even after APNs v1.5 ships, the `birthday_today` payload is **not** added to `buildPayload` — the local path remains the canonical owner.

**Why:**
- **APNs was gated on Apple Developer Program enrollment ($99/yr).** Local notifications need no `.p8` key, no server, no enrollment — they fire from the SDK alone. Shipping the stopgap unblocks the only push category users were asking about (milestone prompts) without waiting on prerequisites the user hadn't completed.
- **Milestones are derived, not stored** (see prior entry). Birthdays are pure functions of `pets.birthday`; they're known to the client as soon as pets load. There's no reason for the server to compute, store, or dispatch a per-pet birthday reminder — the device already has everything it needs.
- **Server-side milestone pushes would duplicate.** If both paths existed, every birthday would produce two pings unless we introduced a feature flag or a `device_tokens`-presence check on the server side. Cleaner to keep the division of responsibility strict: *device-schedulable* events never leave the device; *server-originating* events always route through APNs.
- **Coexistence is automatic.** Both paths carry `{type, target_id}` in the notification payload, and `AppDelegate.userNotificationCenter(_:didReceive:)` forwards both to `DeepLinkRouter.route(type:targetID:)` without distinguishing origin. No routing logic duplication.

**Implications:**
- `buildPayload` in `supabase/functions/dispatch-notification/index.ts` should **not** add a `birthday_today` case. The `type` CHECK in migration 022 still lists it for completeness and to preserve the option of a server-driven reminder for edge cases (e.g. a future "admin push a global pet birthday") — but the default delivery path is local.
- `memory_today` is the one milestone class where APNs remains an option — memory-loop matches depend on post history across years, which is a dynamic server-side computation. v1 ships with no memory reminders; v1.5 may add them via APNs.
- The 09:00 local fire time, the yearly repeat, and the identifier prefix `pawpal.milestone.birthday.<pet_uuid>` are the contract. Reschedule happens on pets-cache change (diffed on `(id, birthday)` tuples) and on scenePhase → active. Signing out cancels all milestone requests.
- The existing priming sheet in `OnboardingView` covers both paths with a single `UNAuthorizationOptions` grant — no separate UX per origin.
- Feb 29 birthdays will skip non-leap years under `UNCalendarNotificationTrigger(repeats: true)`. Not a bug — acceptable for v1, fold-down to Feb 28 convention lives only in the FeedView birthday card. Documented in `docs/known-issues.md`; fix in a later pass by scheduling two requests.
- 64-pending-notification iOS cap applies; one slot per pet, yearly repeat. No action needed unless users routinely own >64 pets.

---

## Playdates are the first pet-to-pet primitive; follow graph stays user-to-user

**Decision:** The `playdates` table (migration 023, 2026-04-18) is the first schema in PawPal that models a direct pet↔pet relationship. `proposer_pet_id` and `invitee_pet_id` both reference `pets(id)`. The existing follow graph (`follows.follower_user_id → followed_user_id`) is **not** extended to pets — they remain user-to-user. `pets.open_to_playdates` gates whether a pet can be invited at all (default flipped from `false` → `true` on 2026-04-19; see the dedicated decision entry below).

**Why:**
- **Playdates are intrinsically pet-to-pet.** Two humans arranging a meetup for their dogs isn't a social-graph action — it's a coordination event between two pet identities. Modeling it as user↔user would throw away the most important slice of the data (which pet is going on the walk). Pets being the social actor has been a core principle since day one (see "Profiles are lightweight; pets are the social actors"); this is the first surface where the schema catches up to that principle.
- **User-to-user follows stay simple.** The feed query is a single `posts WHERE owner_user_id IN (follows.followed_user_id + self)` join. Promoting follows to pet-level would require resolving pet ownership on every feed read. That refactor isn't free and we don't need it — playdates can be pet-to-pet without forcing follows to follow suit.
- **Denormalised `proposer_user_id` / `invitee_user_id` columns on `playdates`** exist so RLS checks (`auth.uid() = proposer_user_id or auth.uid() = invitee_user_id`) don't need a `pets` join on every policy evaluation. The trade is write-time duplication in exchange for read-time simplicity and tighter RLS.
- **`open_to_playdates` default** — originally shipped as `false` (opt-in) on safety grounds. Reversed to `true` (opt-out) on 2026-04-19; see the dedicated "Playdates are opt-out (default on)" entry below for the full reasoning and the retained safety backstops.

**Implications:**
- Future pet-to-pet features (co-play sessions, pet friendship graph, litter/sibling relationships) should follow the playdates pattern: dedicated table with pet id columns + denormalised user ids for RLS, not a generalized "pet_relationships" table.
- Do not repurpose `playdates.proposer_pet_id` / `invitee_pet_id` as a friendship graph. They're event-scoped. If a "pet friends" concept ships, it gets its own table.
- The follow graph is allowed to grow pet-level follow **later** (ROADMAP Phase 4 🔲 entry). When that happens, revisit the feed query cost — it's the gating constraint, not this decision.
- Pet-specific follow should not piggyback on playdates — completing a playdate is not equivalent to following the other pet. Keep the primitives separate.
- The `playdates` SELECT RLS policy grants zero visibility to strangers (only proposer + invitee can read a row). Don't add a "public playdates feed" without a separate `public` boolean column + a policy that's explicit about it.
- `pets.open_to_playdates` is the contract for visibility + the trigger gate. If a future feature wants to invite a pet for something else (group walks, meetups), it should either reuse this flag or add a distinct per-feature flag — don't overload it implicitly.
- Reminders for accepted playdates stay on the **local** notifications path (`UNCalendarNotificationTrigger`) per the "Local notifications own device-schedulable events" decision. The `playdate_invited` push is server-originated (actor isn't the recipient's device), so it correctly lives on APNs — but the T-24h / T-1h / T+2h reminders are device-schedulable and belong to the local path.

---

## Playdates are opt-out (default on); toggle still governs visibility

**Decision:** `pets.open_to_playdates` defaults to `true` as of 2026-04-19 (reversed from `false` in the original migration 023 shipped 2026-04-18). A pet created after migration 023 applies is automatically visible to 约遛弯 invitations. Owners who want the old posture can toggle off in the pet editor (开启遛弯邀请). The BEFORE INSERT trigger on `playdates` (`playdates_gate_invitee_open`) and the visibility gate on `PetProfileView`'s 约遛弯 pill both remain in force — the only thing that changed is the per-row default value.

**Why:**
- **Opt-in default-off suppressed the feature to near-invisibility.** Playdates is the flagship pet-to-pet primitive of Phase 6. A toggle buried in the pet editor, default off, with no onboarding surfacing it means most owners never discover the feature exists. The `约遛弯` pill only appears on someone else's pet profile when *that* pet is open — so with universal default-off, the pill is also universally invisible. The feature can't bootstrap.
- **The data reveal is less severe than the original framing suggested.** A playdate invite reveals a proposed meeting point and time — but only after the invitee *accepts*. Pre-acceptance, the invitee sees the proposer pet + proposed location + time, and can decline silently. No contact info, no precise location of the invitee's home, no automatic exposure. The risk profile is closer to "someone asked you to hang out" than "your address was leaked".
- **The real safety controls are downstream of visibility.** Accepting an invite is an explicit affirmative action by the invitee. The invitee always retains the decline / cancel paths. The pre-composer `PlaydateSafetyInterstitialView` (one-time three-bullet primer) primes new proposers on safety norms. None of these depend on default-off.
- **The toggle remains.** Users who want to opt out can. The toggle lives in `ProfilePetEditorSheet` labelled 开启遛弯邀请 and round-trips through `PetsService.updatePet` → `playdates_gate_invitee_open` trigger. A user who flips it off mid-session is protected by the trigger from any in-flight composer on another device.
- **The iOS editor default matches the DB default.** `ProfilePetEditorSheet` initialises `openToPlaydates = true` for new pets (and for legacy rows where the column decoded as nil). The add-pet flow in `ProfileView` only writes the column explicitly when the user toggles OFF during creation — the ON case is a no-op because the INSERT already wrote `true` via the column default. This keeps the iOS and DB defaults coupled; changing one without the other is a bug.

**Implications:**
- **Do not surface an onboarding-time playdate toggle.** The DB default handles adoption; a dedicated toggle in onboarding adds friction without changing the outcome for the 95% who'd leave it alone.
- **A future "safety review" feature should live on top of the existing `playdates_gate_invitee_open` trigger, not replace it.** If we ever ship a "pause all invites" kill switch, it sets `open_to_playdates = false` via the same column — not a new column.
- **If we localise to a market where default-on isn't acceptable** (EU GDPR legitimate-interest posture, some parental-consent regimes), flip the column default per-region via a settings table, not by reverting this decision globally.
- **Do not re-expand the column semantics.** The column means "this pet is visible for playdate invites" — full stop. Future pet-to-pet invite features (group walks, meetups) should add their own per-feature flag rather than overloading this one, even if they're semantically adjacent.

---

## Story view receipts are owner-visible only; pets are the viewer identity

**Decision:** Migration 024 (2026-04-18) adds `story_views` with primary key `(story_id, viewer_pet_id)`. RLS makes SELECT and DELETE **owner-only** via a subquery against `stories`; a non-owner cannot see the viewer list, and a viewer cannot delete their own view row. The viewing identity is a pet (`viewer_pet_id`), not a user — consistent with PawPal's "pets are the social actors" stance.

**Why:**
- **Owner-only visibility is the common-sense privacy floor.** A viewer expects that "who I watched" is known to the poster; they do not expect that to be public to other viewers. Owner-only SELECT matches Instagram, WeChat Moments, and 小红书 behavior and is the minimum legible contract.
- **Pets as viewer identity keeps the social fiction coherent.** Users already view the app as their pet (their avatar on posts, their name on likes). Showing "{Pet} watched your story" instead of "{User} watched your story" is the same framing, not a new concept.
- **Denormalised `viewer_user_id` enables fast RLS** without a `pets` join on every policy evaluation. Matches the playdates pattern from migration 023. Cost: tiny write-time duplication (one uuid per row) in exchange for simpler / cheaper reads.
- **Viewers can't self-redact.** There is no client-side DELETE for the viewer — once you watch, the story's owner sees it (until the story expires and cascades). This is an MVP tradeoff; a "ghost mode" feature would be opt-in per-user and would gate the client-side `recordView` call. Not shipping that toggle in MVP is a deliberate product choice — it matches Instagram's default behavior.

**Implications:**
- Do NOT add a viewer-facing "delete my view" affordance. The feature is owner-only.
- Do NOT expose `viewerCount` on non-owner surfaces (e.g. on the story rail or in a shared story link). The privacy contract is "owner sees, everyone else doesn't know N".
- Future ghost-mode: introduce `profiles.stories_ghost_mode boolean not null default false`; `StoryService.recordView` early-exits if the caller's profile has the flag set. Ghost-mode stories still show up in the owner's viewer list as "匿名观看" or similar (or simply don't record). Revisit copy when the feature ships.
- Future group-chat-style "seen by X, Y, Z" line on the story viewer itself (non-owner surface) is explicitly NOT on the roadmap — it conflicts with this decision.
- `story_views.viewer_pet_id` means a user with multiple pets could theoretically record multiple rows. MVP client always views as `pets.first`; if we later ship a "viewing as" picker, the dedupe PK still works per-pet.
- If we ever loosen the viewer-list scope (e.g. mutual friends can also see the viewer list), do it via a NEW column on `stories` (e.g. `viewer_list_visibility text not null default 'owner_only'`) plus a revised RLS policy — don't silently change the policy interpretation.

---

## First-party event log; no third-party analytics SDK

**Decision:** Phase 6 instrumentation (D7 retention, posts/DAU, sessions/week) is delivered via a single `public.events` table in PawPal's own Supabase (migration 025) and a fire-and-forget `AnalyticsService.shared` logger on the client. No Firebase Analytics, no Mixpanel, no Amplitude, no Segment, no Sentry, no third-party SDK of any kind. Analytics queries run server-side as `service_role`; the client has no SELECT path into the table.

**Why:**
- **We own the data.** Cohorting, churn analysis, and retention heuristics that reveal PawPal's product trajectory shouldn't live on a vendor's server. Migrating to a new vendor down the road would mean re-ingesting months of events through a different schema and a different definition of "session" — cheaper to own the shape from day one.
- **No PII leakage to vendors.** A third-party SDK pipes event streams to an external endpoint the user has no visibility into and PawPal has no audit trail for. Chinese iOS market reviews vendor SDK lists carefully; shipping without one removes an entire category of review surface and avoids the "which vendor got what" audit question entirely.
- **Fire-and-forget semantics.** Analytics never blocks a user flow, never throws, never surfaces an error. `AnalyticsService.log(_:)` dispatches a detached `Task` and returns on the same RunLoop tick; the insert may or may not succeed, and the caller doesn't care. Matches `StoryService.recordView` and `PushService.clearToken` — every "peripheral" write in the app follows the same log-and-swallow convention.
- **Service-role only read-path.** There's deliberately no SELECT RLS policy on `events`. Analytics runs as `service_role` (bypasses RLS); the client can never introspect another user's event stream, and can never introspect its own stream either. The only read-path is the server-side pipeline — a curious user with `anon` or `authenticated` keys sees zero rows.
- **Privacy-respecting by construction.** The schema accepts `user_id` + `kind` + `properties jsonb` + timestamps — nothing else. No device id (we don't have one), no advertising identifier (we don't link `IDFA`), no IP (already captured by the Postgres connection and never duplicated), no precise location, no user-authored text content (captions, comment bodies, chat messages are not in the properties bag). Properties are dimensional: counts, enums, UUIDs that already live elsewhere in the DB.

**Implications:**
- New event kinds are additive — add a case to `AnalyticsService.Kind`, mirror the string in `supabase/025_events.sql`'s header block, emit. No schema migration required because `properties` is `jsonb` and `kind` is unconstrained `text`.
- Event emission lives on the **success path** of a user-visible action, **after the DB write returned successfully**. Never emit from `catch` blocks, never from computed properties, never inside loops. Failed operations already have `print("[ServiceName] … 失败")` logging.
- `session_start` is client-side deduped to at most one per 30 minutes via `AnalyticsService.logSessionStart()`. Do not bypass this — a server-side DISTINCT can compute the same answer but the raw stream must stay human-readable.
- Opt-out UI and ATT-style prompts are deferred to v1.5. The `TODO(analytics-opt-out)` comment at the top of `AnalyticsService.swift` marks the seam. Until then, every authenticated user contributes; the data pipeline is designed so turning emission off is a one-line early-return in `log(_:)`.
- **Do not reintroduce a third-party analytics SDK** without reopening this decision with the user. That includes "just for crash reporting" (Sentry / Crashlytics) — crash symbols are a separate conversation but the data-flow constraint still applies.
- Retention analysis (D7 cohort, week-N ping) is a server-side aggregation over `events WHERE kind = 'session_start'` grouped by `user_id` and signup-week cohort (derived from `profiles.created_at`). Do not denormalise cohort ids onto `events.properties`; the join at read time is trivial.

---

## Group playdates — junction table, not array columns

**Decision:** Group playdates (1 proposer + 1-2 invitees, hard cap of 3 pets total) are modelled via a new `playdate_participants` junction table (migration 028). The legacy `playdates.proposer_pet_id` / `invitee_pet_id` columns stay as denormalised fast-path fields. `playdates.status` is now a trigger-derived aggregate over the junction rows. All junction writes flow through three SECURITY DEFINER RPCs; there are no client INSERT/UPDATE/DELETE policies on the junction.

**Why:**
- **Per-pet status is first-class.** Each invitee needs to accept / decline independently — two pets invited to the same playdate respond on their own schedule. Array columns (`invitee_pet_ids uuid[]` + a parallel status array) can't represent per-element state without awkward parallel arrays or JSON blobs. The junction gives us a row per pet with its own status and a natural index on `(playdate_id, pet_id)`.
- **Legacy columns preserved, not deprecated.** Every code path that reads `invitee_pet_id` today — the feed card's pair avatar, the 1:1 detail view, notifications, analytics, RLS checks — stays working untouched. The junction is additive. Removing the columns would have turned a "ship group playdates" task into a multi-migration rewrite, with a brief window where old clients see blank invitees. Keeping them denormalised costs two writes per playdate (proposer + first invitee row vs. their own columns) — trivial.
- **Trigger-derived aggregate status keeps the single source of truth.** Feeds, notifications, and the list view all read `playdates.status` — a single scalar. After migration 028 that scalar is recomputed by `derive_playdate_status(pd_id)` on every junction insert/update. Rules, in order: completed stays completed (preserves the migration-026 sweeper); proposer cancelled → cancelled; any invitee declined → declined; proposer + all invitees accepted → accepted; otherwise proposed. The client doesn't need to know the rules — it just reads the column.
- **Hard cap at 3, not unbounded.** The UI surfaces we care about — detail view avatar scroll, feed card, My Playdates row, push-notification copy — all fit 3 pets cleanly without a dedicated group-chat layer. Any N > 3 would force us to design "overflow" UX (avatar stacks, "+2 others" counters, a participants sheet, group chat threading) that we don't want in scope. The cap is enforced server-side by a BEFORE INSERT trigger (`enforce_playdate_participant_count`) — clients can't sneak a 4th pet past validation.
- **Writes flow through SECURITY DEFINER RPCs only.** Three functions own every junction mutation: `accept_playdate_participant`, `decline_playdate_participant`, `cancel_playdate_as_proposer`. Each verifies caller ownership of the target pet before flipping the row, and the cancel RPC cascades every still-pending participant row in one transaction. No client INSERT/UPDATE/DELETE policies on the junction — this keeps the attack surface tiny (three named entry points, each ownership-checked) and the audit trail single-file (mutations always go through a function we control).
- **Second-invitee visibility.** Migration 023's SELECT policy on `playdates` only allowed the proposer + primary-invitee user ids to read the row. A supplementary policy in migration 028 lets any participant (via the junction) read the parent row — without it the second invitee couldn't load the detail view of a group playdate they were invited to.

**Implications:**
- When adding new playdate surfaces, prefer the junction embed (`playdate_participants(*, pets(*), profiles(*))`) as the source of truth for "who's going". The denormalised `invitee_pet_id` column is fine for single-pet 1:1 fast paths, but any surface that needs to show more than one invitee must use the junction.
- Do NOT drop `proposer_pet_id` / `invitee_pet_id` or their NOT NULL constraints. Legacy RLS policies and legacy client code paths depend on them. They're denormalised — treat them as a cached first-participant pair.
- Do NOT add client-side mutation paths to `playdate_participants`. New participant-state transitions must be added as SECURITY DEFINER RPCs that verify caller ownership, update the junction, and let the trigger recompute the parent status.
- Raising the participant cap beyond 3 is a product + design decision, not a DB tweak. It requires revisiting the detail view layout, the feed card, push copy, and the "group chat: out of scope" line in `docs/scope.md` — don't change the trigger in isolation.

---

_Add new entries here when significant architectural, product, or design decisions are made. Changelog captures what changed; this captures why._
