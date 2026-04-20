-- 025_events.sql
-- Date: 2026-04-19
--
-- First-party event log for Phase 6 instrumentation. Closes the final
-- Phase 6 🔲 (Instrumentation — D7 retention, posts/DAU, sessions/week).
--
-- Design philosophy:
--
--   * First-party only. All events land in PawPal's own Supabase, not
--     Firebase Analytics / Mixpanel / Amplitude / Segment. See
--     `docs/decisions.md` → "First-party event log; no third-party
--     analytics SDK". The app is Chinese-first and the Chinese iOS
--     market has a measurably different posture on vendor SDK inclusion
--     — the only way to honour that posture without a second audit per
--     vendor is to not include one.
--
--   * `properties jsonb` instead of strict columns. New event kinds and
--     new properties are additive on the client ("next PR emits
--     `playdate_declined` with `reason`") and should not require a
--     schema migration to start flowing. The kind column plus a JSONB
--     bag is the right trade for a log-shaped table where the write
--     path is append-only and the read path is analytics-only (server-
--     side, not latency-sensitive).
--
--   * No SELECT policy. The client never reads this table — analytics
--     runs server-side as `service_role` against the raw rows (or a
--     derived materialised view). A missing SELECT policy means RLS
--     refuses every client read by default, which is the desired
--     behaviour; we don't want a curious user to scroll anyone else's
--     event stream, and we don't want to leak our own cohorting
--     methodology via what columns the client can introspect.
--
--   * `user_id` is nullable. Pre-auth events exist — `app_open`
--     fires from the App struct's `init()` before the session
--     restores, and a user on the auth screen emitting `signup_viewed`
--     (future) has no `auth.uid()` yet. The WITH CHECK on the insert
--     policy allows a null `user_id` so these rows still land; the
--     `DAU` query simply excludes nulls.
--
--   * `client_at` vs `server_at`. We record both so we can measure
--     clock drift (useful for debugging "why are sessions/week
--     bucketing weird for user X" — likely a device with a misset
--     clock) and so that a retry after a transient failure can reuse
--     the original `client_at` without corrupting the time-series.
--     `server_at` is the authoritative bucketing timestamp for
--     retention/DAU queries; `client_at` is for forensics.
--
--   * Events emitted in this PR (non-exhaustive — new kinds can ship
--     without a schema change):
--       - `app_open`            — App struct init (device-local boot)
--       - `session_start`       — scenePhase → active, debounced 30min
--       - `sign_in`             — AuthManager.signIn success
--       - `sign_up`             — AuthManager.register success
--       - `post_create`         — PostsService.createPost success
--       - `story_view`          — StoryService.recordView success
--       - `story_post`          — StoryService.postStory success
--       - `playdate_proposed`   — PlaydateService.propose success
--       - `playdate_accepted`   — PlaydateService.accept success
--       - `share_tap`           — ShareLink tap (post / pet / profile)
--       - `follow`              — FollowService.follow success
--       - `like`                — PostsService.toggleLike success (insert only)
--       - `comment`             — PostsService.addComment success
--
-- Idempotent and safe to re-apply.

create table if not exists public.events (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references public.profiles(id) on delete cascade,
  kind       text not null,
  properties jsonb,
  client_at  timestamptz not null,
  server_at  timestamptz not null default now()
);

-- Composite (user_id, server_at desc) services the per-user retention
-- query shape ("has user X shown up in the last N days, and in which
-- weeks did they last appear"). The DESC suffix lets the index answer
-- "most recent event" scans without an additional sort.
create index if not exists events_user_at_idx
  on public.events(user_id, server_at desc);

-- (kind, server_at desc) services the per-event-type DAU-style query
-- shape ("how many distinct users emitted `post_create` yesterday").
create index if not exists events_kind_at_idx
  on public.events(kind, server_at desc);

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------
--
-- INSERT: authenticated caller only. `user_id` must match `auth.uid()`
--         — OR be null for pre-auth emission. A non-null `user_id`
--         that doesn't match `auth.uid()` is rejected: a signed-in
--         user MUST NOT be able to forge events attributed to another
--         user (that would pollute every cohort that reads this
--         table). Rows with null `user_id` are accepted from any
--         authenticated session; the analytics pipeline treats them
--         as anonymous samples.
--
-- SELECT: intentionally omitted. The client has no read-path for
--         events. Analytics jobs run server-side as `service_role`,
--         which bypasses RLS by definition.
--
-- UPDATE / DELETE: no policies. Events are immutable append-only; any
--         correction to the analytics layer happens at the read side
--         (filter / dedupe in the query), not by rewriting history.

alter table public.events enable row level security;

drop policy if exists "events_insert_self" on public.events;
create policy "events_insert_self" on public.events
  for insert
  with check (user_id is null or auth.uid() = user_id);

-- Nudge PostgREST to refresh its schema cache so the new table is
-- immediately visible to the iOS client without a project restart.
notify pgrst, 'reload schema';
