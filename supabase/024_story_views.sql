-- 024_story_views.sql
-- Date: 2026-04-18
--
-- Story view receipts — the "seen by" layer for the Stories MVP shipped
-- in migration 018. Completes the Phase 4.5 Stories MVP; scope note
-- from `docs/scope.md` queued this behind external share-out.
--
-- Migration 018 intentionally deferred read-receipts so the rail could
-- ship without a second table. Owners now want to know WHO has looked
-- at a given story (by pet, not by user — PawPal convention) plus a
-- bare view count per story. Viewers get no new UI — views are
-- recorded silently when a story is opened.
--
-- Design notes:
--
--   * Primary key = (story_id, viewer_pet_id) — dedupe is per-pet. A
--     user with 3 pets gets up to 3 rows if they view the story "as"
--     each pet; in the iOS MVP the viewer always views as their first
--     pet (see `StoryViewerView.recordView`), so in practice = 1 row
--     per viewer.
--
--   * `viewer_user_id` is denormalised onto the row so RLS checks
--     don't need a `pets` join on every policy evaluation. Matches the
--     `playdates` table pattern from migration 023 (proposer /
--     invitee user ids denormalised alongside the pet ids).
--
--   * `ON DELETE CASCADE` on both FKs — if the parent story is
--     deleted (owner pulled it / expired cleanup job eventually
--     lands), viewer rows go with it. If the viewer pet is deleted,
--     the rows go with it too. GDPR: deleting a profile already
--     cascades through `pets.owner_user_id`, which now cascades into
--     `story_views.viewer_pet_id` + `.viewer_user_id`.
--
--   * No UPDATE policy — viewer rows are immutable. A `viewed_at`
--     edit has no sensible product meaning, and omitting the policy
--     removes an unnecessary attack surface. The table is
--     append-only-from-viewer, delete-only-from-owner.
--
--   * No DELETE-from-client on the viewer's side — because
--     `viewer_user_id` is denormalised, a viewer CANNOT redact their
--     view without owner cooperation. That's intentional for an MVP;
--     "ghost mode" / per-user privacy toggle is a future feature and
--     explicitly out of scope.
--
-- Prerequisites: migration 018 (stories) must have been applied.
-- Idempotent and safe to re-apply.

create table if not exists public.story_views (
  story_id       uuid not null references public.stories(id)  on delete cascade,
  viewer_pet_id  uuid not null references public.pets(id)     on delete cascade,
  viewer_user_id uuid not null references public.profiles(id) on delete cascade,
  viewed_at      timestamptz not null default now(),
  primary key (story_id, viewer_pet_id)
);

-- The owner's viewer sheet reads "every row for this story, newest
-- first". A composite index on (story_id, viewed_at desc) matches that
-- query shape exactly — no per-row sort once the seek lands.
create index if not exists story_views_story_id_idx
  on public.story_views(story_id, viewed_at desc);

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------
--
-- SELECT: restricted to the story's OWNER. A viewer cannot read the
--         table — this privacy-protects the viewer list from
--         non-owners. Implementation uses a subquery against `stories`
--         keyed on the story id; PostgREST evaluates it against the
--         row being read so the subquery stays O(1) via the stories
--         primary key.
--
-- INSERT: the caller must be recording their own pet viewing.
--         Enforced by the BEFORE INSERT trigger below with
--         SECURITY DEFINER rather than an EXISTS subquery in a
--         with-check expression — matches the
--         `playdates_gate_invitee_open` pattern from migration 023
--         (RLS alone can't cleanly express the cross-table ownership
--         lookup, and a trigger keeps the pet read off the caller's
--         RLS scope so the check can't spuriously fail closed).
--
-- DELETE: story owner only. Matches SELECT rule so owners can prune
--         rows if needed (e.g. a blocked viewer). Viewers cannot
--         delete — see header note on "no ghost mode".
--
-- UPDATE: no policy; rows are immutable.

alter table public.story_views enable row level security;

drop policy if exists "story_views_select_owner" on public.story_views;
create policy "story_views_select_owner" on public.story_views
  for select
  using (
    auth.uid() = (
      select owner_user_id from public.stories where id = story_id
    )
  );

-- INSERT policy gates on `auth.uid() = viewer_user_id` only; the
-- pet-ownership half of the check lives in the BEFORE INSERT trigger
-- below. Splitting the two lets us keep the with-check expression
-- trivially analysable while the more expensive cross-table lookup
-- runs inside a SECURITY DEFINER function.
drop policy if exists "story_views_insert_self" on public.story_views;
create policy "story_views_insert_self" on public.story_views
  for insert
  with check (auth.uid() = viewer_user_id);

drop policy if exists "story_views_delete_owner" on public.story_views;
create policy "story_views_delete_owner" on public.story_views
  for delete
  using (
    auth.uid() = (
      select owner_user_id from public.stories where id = story_id
    )
  );

-- No UPDATE policy — rows are immutable.

-- ---------------------------------------------------------------------
-- pet-ownership gate — BEFORE INSERT trigger
-- ---------------------------------------------------------------------
--
-- Verifies that `viewer_pet_id` belongs to the caller. SECURITY
-- DEFINER so the check can read `pets` regardless of the caller's RLS
-- scope (`pets` SELECT is unrestricted today, but future tightening
-- shouldn't silently break this gate). Pattern copied from
-- `playdates_gate_invitee_open` in migration 023.

create or replace function public.story_views_gate_pet_ownership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _owner uuid;
begin
  select owner_user_id into _owner from public.pets where id = new.viewer_pet_id;
  if _owner is null or _owner <> new.viewer_user_id then
    raise exception 'viewer_pet_not_owned_by_caller'
      using hint = '该毛孩子不属于你';
  end if;
  return new;
end;
$$;

drop trigger if exists story_views_gate_before_insert on public.story_views;
create trigger story_views_gate_before_insert
  before insert on public.story_views
  for each row execute function public.story_views_gate_pet_ownership();

-- Nudge PostgREST to refresh its schema cache so the new table is
-- immediately visible to the iOS client without a project restart.
notify pgrst, 'reload schema';
