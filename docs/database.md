# Database Guide

PawPal uses Supabase (PostgreSQL) as its backend. This guide covers the design philosophy, table structure, and key decisions to keep in mind when making schema changes.

---

## Design Philosophy

**Profiles are lightweight. Pets are the social actors.**

- `profiles` = account identity tied to Supabase auth (login, ownership, search)
- `pets` = rich public social identity (the visible presence in the feed)

Keep human profiles intentionally lean. Pets carry most of the expressive content — bio, breed, personality, photos. When in doubt, put social attributes on `pets`, not `profiles`.

**Social graph connects users, not pets.**

Follows are between user accounts (`follower_user_id → followed_user_id`). This keeps feed queries simple and avoids a complex pet-to-pet relationship layer.

---

## Tables

### profiles
Represents the app-level user account, tied to Supabase auth.

```sql
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  display_name text,
  avatar_url text,
  bio text,
  location_text text,
  privacy_level text not null default 'public',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

- `username` is the stable, searchable identity
- `display_name` is the softer human-facing label
- `email` stays in Supabase auth — do not duplicate it here

---

### pets
The primary social actor. Richer than profiles by design.

```sql
create table pets (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references profiles(id) on delete cascade,
  name text not null,
  avatar_url text,
  species text,
  breed text,
  sex text,
  birthday date,
  age_text text,
  weight text,
  bio text,
  notes text,
  home_city text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

- `bio` is public-facing
- `notes` is owner-facing (private or practical)
- `age_text` supports pets with unknown exact birthdays

---

### posts
Content shared by users, linked to a pet.

```sql
create table posts (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references profiles(id) on delete cascade,
  pet_id uuid references pets(id) on delete set null,
  caption text not null,
  mood text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

- `pet_id` is nullable — if the pet is deleted, posts are preserved with `set null`

---

### post_images
Images attached to a post, ordered by position.

```sql
create table post_images (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references posts(id) on delete cascade,
  image_url text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);
```

---

### follows
Social graph between user accounts.

```sql
create table follows (
  id uuid primary key default gen_random_uuid(),
  follower_user_id uuid not null references profiles(id) on delete cascade,
  followed_user_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint follows_unique unique (follower_user_id, followed_user_id),
  constraint no_self_follow check (follower_user_id <> followed_user_id)
);
```

---

### pet_visits
Social proof for `PetProfileView`. Records one row per unique (pet, viewer, calendar day). See migration `013_pet_visits_and_boops.sql` and CHANGELOG #38.

```sql
create table pet_visits (
  pet_id uuid not null references pets(id) on delete cascade,
  viewer_user_id uuid not null references auth.users(id) on delete cascade,
  visited_on date not null default (now() at time zone 'utc')::date,
  first_visited_at timestamptz not null default now(),
  primary key (pet_id, viewer_user_id, visited_on)
);
```

- The primary key is the dedupe key — `INSERT ... ON CONFLICT DO NOTHING` on the client means same-day refreshes don't double-count, but returning on a new calendar day adds a new row.
- **Owner self-visits are filtered client-side** (the app skips `recordVisit` when `viewer_user_id == pet.owner_user_id`). This is deliberate — keeping the exclusion in app code rather than the RLS policy lets an admin backfill or correct the table without fighting policies.
- Displayed on `PetProfileView` stats card as "访客" with the count being `COUNT(*)` for the pet.

---

### pets.boop_count (column)
Cumulative tap-to-boop counter on the virtual pet. Added in migration 013.

```sql
alter table pets
  add column boop_count integer not null default 0;
```

Updated only via the `increment_pet_boop_count` RPC, never via direct `UPDATE` from the client (to avoid having to loosen the `pets` RLS update policy for non-owners). The RPC is `security definer` and `grant execute ... to authenticated` — any signed-in user can boop any pet.

```sql
create function increment_pet_boop_count(
  pet_id uuid,
  by_count integer default 1
) returns integer
  language plpgsql
  security definer
  set search_path = public;
```

Displayed on `PetProfileView` stats card as "摸摸". The client debounces taps over ~1.8s and flushes an aggregate delta, so a burst of 10 taps becomes one RPC call with `by_count = 10`.

---

### pets.accessory (column)
Persisted virtual-pet dress-up state. Added in migration 014 / CHANGELOG #39.

```sql
alter table pets
  add column accessory text;

alter table pets
  add constraint pets_accessory_check
  check (accessory is null or accessory in ('none', 'bow', 'hat', 'glasses'));
```

Written by owners only (the existing `pets` UPDATE RLS policy restricts UPDATEs to `owner_user_id = auth.uid()`). The CHECK constraint rejects unknown values so a bad client build can't leave us with arbitrary strings the renderer can't map to `DogAvatar.Accessory`. Nil / missing is treated as `'none'` by the client for rows written before the migration landed.

Read inside `RemotePet.virtualPetState(stats:posts:now:)` — when the virtual pet stage mounts, the saved accessory is rendered immediately instead of resetting to bare-headed.

---

### pets.open_to_playdates (column)
Visibility gate for receiving playdate invitations. Added in migration 023 / CHANGELOG #53; default flipped from `false` → `true` on 2026-04-19.

```sql
alter table pets
  add column if not exists open_to_playdates boolean not null default true;
```

- Default is `true` — a pet created after migration 023 applies is automatically visible to 约遛弯 invitations. Owners who prefer the old posture can toggle off via 开启遛弯邀请 in `ProfilePetEditorSheet`.
- The iOS 约遛弯 pill on `PetProfileView` is gated on this flag; a BEFORE INSERT trigger on `playdates` (`playdates_gate_invitee_open`) is defense-in-depth against stale UI states (toggle flipped off after the composer opened).
- Rationale for the flip: opt-in default-off suppressed the feature to near-invisibility during internal testing — most users never found the toggle in the pet editor. See `docs/decisions.md` → "Playdates are opt-out (default on); toggle still governs visibility".

---

### playdates
First pet-to-pet graph edge in the schema. Added in migration 023 / CHANGELOG #53. See `docs/decisions.md` → "Playdates are the first pet-to-pet primitive; follow graph stays user-to-user".

```sql
create table playdates (
  id uuid primary key default gen_random_uuid(),
  proposer_pet_id  uuid not null references pets(id)     on delete cascade,
  invitee_pet_id   uuid not null references pets(id)     on delete cascade,
  proposer_user_id uuid not null references profiles(id) on delete cascade,
  invitee_user_id  uuid not null references profiles(id) on delete cascade,
  scheduled_at   timestamptz not null,
  location_name  text not null,
  location_lat   numeric,
  location_lng   numeric,
  status text not null default 'proposed'
    check (status in ('proposed','accepted','declined','cancelled','completed')),
  message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint no_self_playdate check (proposer_pet_id <> invitee_pet_id)
);

create index playdates_invitee_status_idx  on playdates(invitee_user_id, status);
create index playdates_proposer_status_idx on playdates(proposer_user_id, status);
create index playdates_scheduled_at_idx    on playdates(scheduled_at);
```

- **Both user_id columns are denormalised from the pet rows.** This is deliberate — RLS policies (`auth.uid() = proposer_user_id or auth.uid() = invitee_user_id`) need a fast check without a `pets` join. Worth the tiny write-time duplication.
- **RLS is airtight.** SELECT, UPDATE, DELETE are gated on participant-only; INSERT is gated on `auth.uid() = proposer_user_id AND proposer pet is owned by the caller`. Strangers see zero rows.
- **BEFORE INSERT trigger `playdates_gate_invitee_open`** enforces that the invitee pet has `open_to_playdates = true`. `SECURITY DEFINER` so the check reads `pets` regardless of the caller's RLS scope.
- **AFTER INSERT trigger `playdates_notify_invited`** calls `queue_notification(invitee_user_id, proposer_user_id, 'playdate_invited', playdate_id)` — the APNs path is owned by the edge function's `playdate_invited` branch.
- Status transitions (client-enforced, `CHECK`-bounded): `proposed → accepted | declined | cancelled`, `accepted → cancelled | completed`. The `accepted → completed` transition is now backed by a server-side pg_cron sweeper (see `sweep_completed_playdates` below); the note in `docs/scope.md` about a deferred sweeper is resolved as of migration 026.
- **Weekly-repeat series (migration 027).** Two additive columns — `series_id uuid` and `series_sequence smallint` (1..4) — group 4 sibling playdates created from the composer's "每周重复" toggle. Both columns are nullable; one-off playdates leave them null. A partial index `idx_playdates_series on playdates(series_id) where series_id is not null` keeps lookups fast without bloating the index on the common one-off path. There is intentionally no FK on `series_id` and no parent `playdate_series` table — a series is defined implicitly as the set of rows sharing the uuid. Cancelling "整个系列" issues a single `UPDATE playdates SET status = 'cancelled' WHERE series_id = $1 AND status IN ('proposed','accepted') AND scheduled_at > now()`; past instances and already-finalised rows are untouched. `series_id` is orthogonal to the group-playdate participant junction (migration 028) — a group playdate can also belong to a series, and the junction simply has rows for each of the series's playdate ids.
- **Group playdates (migration 028).** The `proposer_pet_id` / `invitee_pet_id` columns stay — they're the fast-path 1:1 denormalisation for legacy code and RLS checks. The new canonical source of truth for "which pets are going" is the junction table `playdate_participants` (see below). `playdates.status` is now a trigger-derived aggregate over the junction rows (proposer cancel → `cancelled`, any invitee decline → `declined`, proposer + all invitees accepted → `accepted`, otherwise `proposed`). The parent row's `status` column is still the single authoritative value surfaces like the feed / My Playdates list read.

---

### playdate_participants
Junction table connecting one playdate to 2-3 pets (1 proposer + 1-2 invitees). Added in migration 028. See `docs/decisions.md` → "Group playdates — junction table, not array columns".

```sql
create table playdate_participants (
  playdate_id uuid not null references playdates(id) on delete cascade,
  pet_id      uuid not null references pets(id)       on delete cascade,
  user_id     uuid not null references profiles(id)   on delete cascade,
  role   text not null check (role   in ('proposer','invitee')),
  status text not null check (status in ('proposed','accepted','declined','cancelled')),
  joined_at timestamptz not null default now(),
  primary key (playdate_id, pet_id)
);

create index idx_pdp_user   on playdate_participants(user_id);
create index idx_pdp_pet    on playdate_participants(pet_id);
create index idx_pdp_status on playdate_participants(status);
```

- **Composite primary key `(playdate_id, pet_id)`.** A pet can't be invited twice to the same playdate, and the compound key keeps the table narrow — no surrogate id column.
- **Participant count is capped at 2-3** by a BEFORE INSERT trigger (`enforce_playdate_participant_count`). The lower bound (≥ 2) is a client contract: the composer always inserts the proposer + at least one invitee in one transaction. The upper bound (≤ 3) is enforced server-side — the trigger rejects inserts when the existing count already equals 3. Rationale: 3 pets fit in the scheduling surfaces (detail-view horizontal scroll, feed avatar stack, push-notification copy) without needing a dedicated group-chat surface, which is out of scope.
- **Per-pet `status` is independent.** Each invitee can accept / decline on their own row without affecting siblings. The top-level `playdates.status` is recomputed from all rows by the `sync_playdate_status_from_participants` AFTER INSERT/UPDATE trigger, which calls `derive_playdate_status(pd_id)` — rules in the order they're applied:
  1. If the parent is already `completed`, keep `completed` (preserves the migration-026 sweeper's writes).
  2. If the proposer row is `cancelled`, aggregate → `cancelled`.
  3. If any invitee row is `declined`, aggregate → `declined`.
  4. If the proposer + every invitee is `accepted`, aggregate → `accepted`.
  5. Otherwise → `proposed`.
  The trigger only writes the parent row when the aggregate actually changes, so it's cheap to re-evaluate on every junction update.
- **RLS: reads self-referential, writes via SECURITY DEFINER RPCs only.** The SELECT policy returns rows where `auth.uid()` is either the participant's `user_id` or a co-participant on the same `playdate_id`. There are no INSERT / UPDATE / DELETE client policies — all writes flow through three RPCs: `accept_playdate_participant(pd_id, my_pet_id)`, `decline_playdate_participant(pd_id, my_pet_id)`, `cancel_playdate_as_proposer(pd_id)`. Each verifies caller ownership of the target pet, flips the junction row, and lets the trigger recompute the parent status. The cancel RPC also cascades every still-pending participant row to `cancelled` in one transaction.
- **Supplementary SELECT policy on `playdates`.** Migration 023's SELECT policy only allowed the proposer + primary invitee to read the row. Migration 028 adds a supplementary policy so any participant (via the junction) can read the parent row — without it, the second invitee on a group playdate couldn't load the detail view.
- **Backfill.** Migration 028 seeds every legacy `playdates` row with two participant rows (proposer + invitee), with per-pet status derived from the parent: proposer is `'accepted'` (unless the parent is `cancelled`), invitee mirrors the parent status (with `'completed'` collapsed to `'accepted'`). The insert is `on conflict do nothing` so re-applying the migration is safe.
- **The `participants` PostgREST embed** is requested via `playdate_participants(*, pets(*), profiles(*))` on detail and list fetches. It's optional — legacy code paths that skip the embed still decode, and the iOS model falls back to synthesising two rows from the denormalised `proposer_*` / `invitee_*` columns.

---

### sweep_completed_playdates (pg_cron job)
Server-side sweeper that flips `playdates.status` from `accepted` → `completed` at T+2h after `scheduled_at`. Added in migration 026.

```sql
create or replace function sweep_completed_playdates()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update playdates
     set status = 'completed',
         updated_at = now()
   where status = 'accepted'
     and scheduled_at < now() - interval '2 hours';
end;
$$;

-- scheduled via pg_cron (extensions schema) every 15 minutes:
--   cron.schedule('sweep_completed_playdates', '*/15 * * * *',
--                 'select public.sweep_completed_playdates();')
```

- **Why it exists.** Before migration 026 the `accepted → completed` flip depended on a local iOS notification at T+2h. If the user didn't open the app inside the notification window — notifications denied, app reinstalled, phone off — the row stayed `accepted` forever. The sweeper guarantees eventual consistency: by T+2h15m at the latest, any accepted playdate past its +2h mark is server-side completed.
- **15-minute cadence** is a deliberate freshness-vs-load trade. Playdate surfaces already render relative time, so a ±15min lag on the status flip is imperceptible. 1-minute polling would be wasteful; hourly would leave visibly stale rows.
- **`SECURITY DEFINER` is documentary.** pg_cron runs jobs as postgres by default, so strict RLS bypass isn't required for the cron path. Declaring `SECURITY DEFINER` documents intent (the function is designed to update rows across ALL users) and lets operators call it manually from the SQL editor or a future edge function without needing superuser privileges.
- **pg_cron is a prerequisite.** `create extension if not exists pg_cron with schema extensions;` will error on Supabase plans / projects where pg_cron is not enabled. Operator must enable pg_cron manually (Database → Extensions → pg_cron) before applying migration 026. Once enabled, the migration is safe to re-run — the extension creation is a no-op, and the cron-schedule block is gated on a `cron.job.jobname` lookup.
- **Idempotent schedule.** The `do $$ ... end $$` block in migration 026 only schedules the job if a row with `jobname = 'sweep_completed_playdates'` is absent from `cron.job`. Re-applying the migration does not churn the job id, so any admin-side observability keyed on the id survives re-runs.

---

### story_views
Seen-by / view-counts layer for ephemeral stories. Added in migration 024 / CHANGELOG #55.

```sql
create table story_views (
  story_id       uuid not null references stories(id)  on delete cascade,
  viewer_pet_id  uuid not null references pets(id)     on delete cascade,
  viewer_user_id uuid not null references profiles(id) on delete cascade,
  viewed_at      timestamptz not null default now(),
  primary key (story_id, viewer_pet_id)
);

create index story_views_story_id_idx on story_views(story_id, viewed_at desc);
```

- **Primary key `(story_id, viewer_pet_id)`** — dedupe is per-pet. A user with multiple pets could theoretically record multiple rows by viewing "as" each pet, but MVP client-side always views as `pets.first`, so effectively = 1 row per viewer.
- **`viewer_user_id` is denormalised** onto the row so RLS checks don't need a `pets` join on every policy evaluation. Matches the `playdates` pattern from migration 023.
- **`ON DELETE CASCADE` on both FKs** — when a story is deleted (or cleaned up after its 24h TTL) the viewer rows go with it; when a pet is deleted its viewer rows go with it.
- **RLS is asymmetric and airtight.** SELECT + DELETE are owner-only via a subquery against `stories` (`auth.uid() = (select owner_user_id from stories where id = story_id)`); a non-owner cannot read the viewer list. INSERT requires `auth.uid() = viewer_user_id` and a SECURITY DEFINER BEFORE INSERT trigger `story_views_gate_pet_ownership` enforces that the viewer pet belongs to the caller (mirrors `playdates_gate_invitee_open`). There is no UPDATE policy — rows are immutable.
- **Viewers cannot self-delete.** The denormalisation design means viewers can't redact their view without owner cooperation. This is intentional for MVP — a future "ghost mode" would add a per-user privacy toggle that gates the client-side `recordView` call.

---

### events
First-party event log for Phase 6 instrumentation (D7 retention, posts/DAU, sessions/week). Added in migration 025. See `docs/decisions.md` → "First-party event log; no third-party analytics SDK".

```sql
create table events (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references profiles(id) on delete cascade,
  kind       text not null,
  properties jsonb,
  client_at  timestamptz not null,
  server_at  timestamptz not null default now()
);

create index events_user_at_idx on events(user_id, server_at desc);
create index events_kind_at_idx on events(kind, server_at desc);
```

- **`properties` is `jsonb`, not strict columns.** New event kinds and new property keys are additive on the client — they should not require a schema migration to start flowing. The table is append-only, write-heavy, read-only-server-side; the JSONB bag is the right trade.
- **`user_id` is nullable.** Pre-auth events (`app_open` fired from the App struct's `init()` before the session restores) land with `user_id = null`. The INSERT RLS policy allows this explicitly. Retention queries filter nulls.
- **`client_at` vs `server_at`.** `server_at` is the authoritative bucketing timestamp for retention / DAU queries. `client_at` is captured on the device at emission time and lets us measure clock drift + replay a queued event without corrupting the time-series.
- **RLS is asymmetric.** INSERT requires `user_id is null OR auth.uid() = user_id` (so an authenticated user can't forge events attributed to another user). **No SELECT policy** — the client has zero read-path; analytics runs server-side as `service_role`. No UPDATE / DELETE policy — events are immutable.
- **Event kinds emitted in migration 025 (non-exhaustive):** `app_open`, `session_start`, `sign_in`, `sign_up`, `post_create`, `story_view`, `story_post`, `playdate_proposed`, `playdate_accepted`, `share_tap`, `follow`, `like`, `comment`. New kinds can be emitted without a schema change.
- **Do not join client reads against this table.** There is no SELECT policy by design. Do not add one without reopening the decision in `docs/decisions.md`.

---

## Indexes

```sql
create index idx_pets_owner_user_id on pets(owner_user_id);
create index idx_posts_owner_user_id on posts(owner_user_id);
create index idx_posts_pet_id on posts(pet_id);
create index idx_posts_created_at on posts(created_at desc);
create index idx_post_images_post_id on post_images(post_id);
create index idx_follows_follower_user_id on follows(follower_user_id);
create index idx_follows_followed_user_id on follows(followed_user_id);
create index idx_pet_visits_pet_id on pet_visits(pet_id);
create index idx_pet_visits_viewer_user_id on pet_visits(viewer_user_id);
create index idx_pet_visits_visited_on on pet_visits(visited_on desc);
create index playdates_invitee_status_idx on playdates(invitee_user_id, status);
create index playdates_proposer_status_idx on playdates(proposer_user_id, status);
create index playdates_scheduled_at_idx on playdates(scheduled_at);
create index idx_playdates_series on playdates(series_id) where series_id is not null;
create index story_views_story_id_idx on story_views(story_id, viewed_at desc);
create index events_user_at_idx on events(user_id, server_at desc);
create index events_kind_at_idx on events(kind, server_at desc);
```

---

## Feed Query Shape

The home feed retrieves posts where:
- `owner_user_id` is the current user, **or**
- `owner_user_id` is someone the current user follows

Ordered by `created_at desc`.

---

## Adding or Changing Tables

- Add new SQL files under `supabase/` with a numeric prefix (e.g. `012_add_tags.sql`)
- Apply in order — migrations are cumulative
- Update this doc if the schema or design philosophy changes
- Never modify existing migration files — add a new one instead
