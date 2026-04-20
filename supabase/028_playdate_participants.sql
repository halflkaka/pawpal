-- 028_playdate_participants.sql
-- Date: 2026-04-19
--
-- Group playdates — the first playdate-shape change since migration 023
-- introduced the 1:1 primitive. One proposer can now invite one OR two
-- other pets (2-3 pets total per playdate), modelled via a new junction
-- table `public.playdate_participants` keyed on `(playdate_id, pet_id)`
-- with per-pet `status` so each invitee can accept / decline
-- independently. The top-level `playdates.status` becomes a derived
-- aggregate over the per-participant statuses, kept in sync by trigger.
--
-- Why a junction, not array columns on `playdates`:
--
--   * A `invitee_pet_ids uuid[]` column looks cheap until you try to
--     write the RLS SELECT policy. "Can this auth.uid() read the row?"
--     needs "is auth.uid() the proposer, OR does auth.uid() own any pet
--     whose id is in invitee_pet_ids?" — that second clause is a
--     cross-table EXISTS against `pets` for every row evaluation and
--     PostgREST can't cache it. A junction turns visibility into a
--     single "is there a row in playdate_participants with this
--     playdate_id and my user_id?" lookup, which is a covered index
--     read.
--
--   * Per-participant status. In the 1:1 world, one status on the
--     parent row is enough — there's only one invitee to accept or
--     decline. With 2 invitees we need to know which one said yes and
--     which one said no independently. A junction row per pet is the
--     only shape that makes this legible; a parallel `statuses text[]`
--     aligned by index with `invitee_pet_ids` would be a fragile
--     encoding that Postgres can't constrain.
--
--   * Per-participant "joined_at" and future metadata (rsvp_message?
--     ride-along flags?) live naturally on the junction row. Adding
--     them later to array-encoded alternatives would force a migration
--     + a client rewrite.
--
-- What is NOT dropped:
--
--   * `playdates.proposer_pet_id` / `invitee_pet_id` / `proposer_user_id`
--     / `invitee_user_id` — retained as **denormalised fast-path**
--     columns. The junction table is the canonical source of truth;
--     the columns are convenience fields read by the legacy 1:1 UI
--     code path without requiring a join. For group playdates, the
--     `invitee_*` columns represent the FIRST invitee (the "primary"
--     invitee slot) — older code paths that only know how to display
--     two avatars still render something reasonable, and new code
--     paths prefer the junction embed.
--
--   * `playdates.status` (the top-level column) — retained and kept in
--     sync by the new `sync_playdate_status_from_participants` trigger
--     that re-derives it after any INSERT / UPDATE on the junction.
--     Callers that only care about the aggregate (the `accepted` →
--     `completed` sweeper from migration 026, the FeedView countdown
--     card filter, etc.) keep working unchanged. The CHECK constraint
--     on `status` from migration 023 is unchanged.
--
--   * None of the RLS policies on `playdates` itself. Visibility
--     remains proposer/invitee-only on the legacy columns; group
--     playdates compose with the new per-participant RLS on the
--     junction. A user in the junction but not on the legacy columns
--     (a "second invitee") will read the junction rows via the
--     policy below, but would NOT be able to read the parent
--     playdate row through the migration-023 SELECT policy — which
--     means we have to add a second SELECT policy on `playdates` so
--     junction members can read the parent row too.
--
-- Why cap participants at 3 (proposer + up to 2 invitees):
--
--   * Venue / coordination friction rises sharply past three pets.
--     MVP use case is "me + a friend's pet" or "me + two friends'
--     pets". Larger groups are a different product (meetup / group
--     walk) that deserves its own schema and RLS story.
--
--   * The cap is enforced via a BEFORE INSERT trigger rather than a
--     CHECK constraint because Postgres CHECKs can't reference other
--     rows in the same table. The trigger is cheap — indexed count()
--     on `(playdate_id)` — and only fires on junction inserts, which
--     are bounded at 3 per playdate.
--
--   * Raising the cap to N later is a one-line change in
--     `enforce_playdate_participant_count`. Lowering is harder (would
--     require backfilling a delete path), so err high at your peril.
--
-- How the derived top-level status works:
--
--   * 'cancelled'  — the proposer's junction row is 'cancelled'. This
--     is the "proposer cancelled the whole thing" terminal state.
--   * 'declined'   — any invitee row is 'declined'. Even one "no"
--     breaks the playdate because the venue + timing was proposed for
--     the specific group; silently dropping a declining invitee and
--     continuing with the others would violate the proposer's
--     expectations.
--   * 'accepted'   — proposer is 'accepted' AND every invitee is
--     'accepted'. This is the "all green" state that unlocks the
--     countdown cards and local reminders.
--   * 'completed'  — preserved verbatim. The migration-026 sweeper
--     flips `accepted → completed` at T+2h and we do NOT re-derive
--     away from 'completed' (the derive function short-circuits).
--   * 'proposed'   — the default when no terminal condition is met.
--
--   * The trigger function `sync_playdate_status_from_participants`
--     runs AFTER INSERT OR UPDATE on the junction, calls
--     `derive_playdate_status(pd_id)`, and writes the result back to
--     `playdates.status` — but only if it would change, to avoid
--     firing the `updated_at` trigger redundantly.
--
-- Backfill: every existing `playdates` row is seeded with two junction
-- rows so the 1:1 MVP continues to work with the new data model:
--
--   * A 'proposer' row mirroring proposer_pet_id / proposer_user_id.
--     Status starts as 'accepted' (if the parent row isn't 'cancelled')
--     or 'cancelled' (if the parent is) — the 1:1 model treated the
--     proposer as having implicitly committed on insert, so the
--     junction faithfully reflects that.
--   * An 'invitee' row mirroring invitee_pet_id / invitee_user_id.
--     Status mirrors the parent `playdates.status` as-is — that's the
--     whole reason the 1:1 column existed.
--
-- `on conflict do nothing` gates the backfill so re-running the
-- migration is safe.
--
-- Prerequisites: migrations 023 (playdates), 026 (sweeper), 027
-- (series_id) must have been applied. Idempotent and safe to re-apply.

-- ---------------------------------------------------------------------
-- playdate_participants — junction
-- ---------------------------------------------------------------------
create table if not exists public.playdate_participants (
  playdate_id uuid not null references public.playdates(id) on delete cascade,
  pet_id      uuid not null references public.pets(id)      on delete cascade,
  user_id     uuid not null references public.profiles(id)  on delete cascade,
  role        text not null check (role in ('proposer','invitee')),
  status      text not null default 'proposed'
    check (status in ('proposed','accepted','declined','cancelled')),
  joined_at   timestamptz not null default now(),
  primary key (playdate_id, pet_id)
);

create index if not exists idx_pdp_user
  on public.playdate_participants(user_id);
create index if not exists idx_pdp_pet
  on public.playdate_participants(pet_id);
create index if not exists idx_pdp_status
  on public.playdate_participants(playdate_id, status);

-- ---------------------------------------------------------------------
-- Backfill — seed junction rows for every existing playdate
-- ---------------------------------------------------------------------
--
-- The 1:1 MVP treated the proposer as having already committed the
-- moment they created the row; their junction row therefore lands as
-- 'accepted' (or 'cancelled', if the parent is terminally cancelled).
-- The invitee's row mirrors the parent's status exactly — that was the
-- whole point of the top-level column pre-this-migration.
--
-- `on conflict do nothing` gates both inserts so the migration is safe
-- to re-run on a database where a subset of junction rows already exist
-- (e.g. after a partial earlier apply).

insert into public.playdate_participants
  (playdate_id, pet_id, user_id, role, status)
select
  p.id,
  p.proposer_pet_id,
  p.proposer_user_id,
  'proposer',
  case when p.status = 'cancelled' then 'cancelled' else 'accepted' end
from public.playdates p
on conflict (playdate_id, pet_id) do nothing;

insert into public.playdate_participants
  (playdate_id, pet_id, user_id, role, status)
select
  p.id,
  p.invitee_pet_id,
  p.invitee_user_id,
  'invitee',
  -- Parent statuses the junction can carry verbatim. 'completed' is
  -- a top-level-only aggregate — collapse it to 'accepted' on the
  -- junction (an invitee whose playdate completed had, by definition,
  -- accepted it).
  case
    when p.status = 'completed' then 'accepted'
    else p.status
  end
from public.playdates p
on conflict (playdate_id, pet_id) do nothing;

-- ---------------------------------------------------------------------
-- Derive top-level status from junction rows
-- ---------------------------------------------------------------------
create or replace function public.derive_playdate_status(pd_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  _proposer_status text;
  _declined_count  int;
  _accepted_count  int;
  _invitee_count   int;
  _current_parent  text;
begin
  -- Preserve 'completed' — the migration-026 sweeper owns that
  -- transition, and re-deriving to 'accepted' after completion would
  -- race the sweeper on every junction touch.
  select status into _current_parent from public.playdates where id = pd_id;
  if _current_parent = 'completed' then
    return 'completed';
  end if;

  select status into _proposer_status
  from public.playdate_participants
  where playdate_id = pd_id and role = 'proposer'
  limit 1;

  -- Proposer cancelled — terminal 'cancelled'.
  if _proposer_status = 'cancelled' then
    return 'cancelled';
  end if;

  -- Any invitee declined — parent goes 'declined'. One dissent breaks
  -- the group because the venue + timing were proposed for this
  -- specific set of pets.
  select count(*) into _declined_count
  from public.playdate_participants
  where playdate_id = pd_id
    and role = 'invitee'
    and status = 'declined';
  if _declined_count > 0 then
    return 'declined';
  end if;

  -- All green — proposer accepted + every invitee accepted.
  select count(*) into _invitee_count
  from public.playdate_participants
  where playdate_id = pd_id and role = 'invitee';

  select count(*) into _accepted_count
  from public.playdate_participants
  where playdate_id = pd_id and role = 'invitee' and status = 'accepted';

  if _proposer_status = 'accepted'
     and _invitee_count > 0
     and _accepted_count = _invitee_count then
    return 'accepted';
  end if;

  -- Everything else — still in-flight.
  return 'proposed';
end;
$$;

-- ---------------------------------------------------------------------
-- Sync trigger — keep playdates.status in sync with the junction
-- ---------------------------------------------------------------------
--
-- Runs AFTER INSERT OR UPDATE on playdate_participants. Calls
-- derive_playdate_status and only writes back when the result would
-- change — avoids re-firing updated_at triggers on no-op derivations.

create or replace function public.sync_playdate_status_from_participants()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _pd_id uuid;
  _new_status text;
  _current_status text;
begin
  _pd_id := coalesce(new.playdate_id, old.playdate_id);
  _new_status := public.derive_playdate_status(_pd_id);

  select status into _current_status from public.playdates where id = _pd_id;

  if _current_status is distinct from _new_status then
    update public.playdates
       set status = _new_status,
           updated_at = now()
     where id = _pd_id;
  end if;

  return null;  -- AFTER trigger — return value is ignored
end;
$$;

drop trigger if exists sync_playdate_status on public.playdate_participants;
create trigger sync_playdate_status
  after insert or update on public.playdate_participants
  for each row execute function public.sync_playdate_status_from_participants();

-- ---------------------------------------------------------------------
-- Participant-count cap trigger — BEFORE INSERT
-- ---------------------------------------------------------------------
--
-- Rejects inserts that would push the playdate over 3 participants.
-- We only check the upper bound — the lower bound (>= 2) is the
-- client's responsibility (the propose flow inserts all 2-3 rows
-- together). Enforcing >=2 on insert would be impossible anyway:
-- the very first junction row for a new playdate is legitimately
-- the only row at that instant.

create or replace function public.enforce_playdate_participant_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _count int;
begin
  select count(*) into _count
  from public.playdate_participants
  where playdate_id = new.playdate_id;

  if _count >= 3 then
    raise exception 'playdate_participant_cap_exceeded'
      using hint = '一次遛弯最多 3 只毛孩子';
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_participant_count on public.playdate_participants;
create trigger enforce_participant_count
  before insert on public.playdate_participants
  for each row execute function public.enforce_playdate_participant_count();

-- ---------------------------------------------------------------------
-- RLS on playdate_participants
-- ---------------------------------------------------------------------
--
-- SELECT: a user can read participant rows for any playdate they are
-- themselves participating in. The subquery is self-referential (it
-- queries the same table) but this is safe because auth.uid() is a
-- constant within a query — Postgres evaluates the EXISTS once per
-- row-to-check, not recursively. The INDEX on (user_id) keeps the
-- lookup O(1) per candidate row.
--
-- INSERT / UPDATE / DELETE: NO direct client-facing policies. All
-- writes go through SECURITY DEFINER functions (accept / decline /
-- cancel_as_proposer, + the propose flow which inserts via service
-- role semantics on the server side of PlaydateService). This is the
-- same posture as the `notifications` table from migration 022 — the
-- canonical source of truth for per-participant state shouldn't be
-- writable by arbitrary clients except through the well-defined
-- transition RPCs.

alter table public.playdate_participants enable row level security;

drop policy if exists "pdp_select_own_playdates" on public.playdate_participants;
create policy "pdp_select_own_playdates" on public.playdate_participants
  for select using (
    exists (
      select 1 from public.playdate_participants pdp2
      where pdp2.playdate_id = playdate_participants.playdate_id
        and pdp2.user_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------
-- Supplementary SELECT policy on playdates — junction members
-- ---------------------------------------------------------------------
--
-- Migration 023's SELECT policy only lets proposer / primary-invitee
-- read the parent row. For group playdates with a SECOND invitee, the
-- second invitee is in the junction but NOT on the legacy
-- `invitee_user_id` column, so they couldn't read the parent row
-- without this extra policy. The additional policy unions visibility
-- to any user with a junction row on the same playdate.

drop policy if exists "playdates_select_participants_via_junction" on public.playdates;
create policy "playdates_select_participants_via_junction" on public.playdates
  for select
  using (
    exists (
      select 1 from public.playdate_participants pdp
      where pdp.playdate_id = playdates.id
        and pdp.user_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------
-- RPC: accept_playdate_participant
-- ---------------------------------------------------------------------
--
-- The invitee calls this to flip their junction row to 'accepted'.
-- Callers must own `my_pet_id` (else the RPC is a no-op that raises).
-- Security-definer so the write doesn't need a client-facing UPDATE
-- policy. The trigger re-derives top-level status after the write.

create or replace function public.accept_playdate_participant(
  pd_id uuid,
  my_pet_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  _caller uuid := auth.uid();
  _owner  uuid;
begin
  if _caller is null then
    raise exception 'not_authenticated';
  end if;

  select owner_user_id into _owner from public.pets where id = my_pet_id;
  if _owner is null or _owner <> _caller then
    raise exception 'pet_not_owned_by_caller'
      using hint = '只能替自己的毛孩子回复邀请';
  end if;

  update public.playdate_participants
     set status = 'accepted'
   where playdate_id = pd_id
     and pet_id = my_pet_id
     and user_id = _caller
     and status in ('proposed','declined');
  -- If no row matched, the pet isn't a participant on this playdate;
  -- fail loud so the client can show a real error rather than silently
  -- doing nothing.
  if not found then
    raise exception 'participant_row_not_found'
      using hint = '找不到对应的邀请';
  end if;
end;
$$;

grant execute on function public.accept_playdate_participant(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- RPC: decline_playdate_participant
-- ---------------------------------------------------------------------
--
-- Symmetric to `accept_playdate_participant`. Flips the caller's
-- junction row to 'declined'. The derive function will collapse the
-- top-level status to 'declined' since even a single dissent breaks
-- the group (see header comment).

create or replace function public.decline_playdate_participant(
  pd_id uuid,
  my_pet_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  _caller uuid := auth.uid();
  _owner  uuid;
begin
  if _caller is null then
    raise exception 'not_authenticated';
  end if;

  select owner_user_id into _owner from public.pets where id = my_pet_id;
  if _owner is null or _owner <> _caller then
    raise exception 'pet_not_owned_by_caller'
      using hint = '只能替自己的毛孩子回复邀请';
  end if;

  update public.playdate_participants
     set status = 'declined'
   where playdate_id = pd_id
     and pet_id = my_pet_id
     and user_id = _caller
     and status in ('proposed','accepted');
  if not found then
    raise exception 'participant_row_not_found'
      using hint = '找不到对应的邀请';
  end if;
end;
$$;

grant execute on function public.decline_playdate_participant(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- RPC: cancel_playdate_as_proposer
-- ---------------------------------------------------------------------
--
-- The proposer calls this to cancel the entire playdate. Flips every
-- junction row (proposer + all invitees) to 'cancelled' and the
-- parent row to 'cancelled' directly (belt-and-suspenders — the
-- derive trigger would arrive at the same answer, but writing the
-- parent here makes the transition atomic from the caller's POV).
--
-- Only the proposer can call this. Invitees who want out use
-- `decline_playdate_participant`.

create or replace function public.cancel_playdate_as_proposer(pd_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  _caller uuid := auth.uid();
  _is_proposer boolean;
begin
  if _caller is null then
    raise exception 'not_authenticated';
  end if;

  select exists(
    select 1 from public.playdate_participants
    where playdate_id = pd_id
      and user_id = _caller
      and role = 'proposer'
  ) into _is_proposer;

  if not _is_proposer then
    raise exception 'not_proposer'
      using hint = '只有发起人可以取消整场遛弯';
  end if;

  update public.playdate_participants
     set status = 'cancelled'
   where playdate_id = pd_id
     and status in ('proposed','accepted');

  update public.playdates
     set status = 'cancelled',
         updated_at = now()
   where id = pd_id
     and status <> 'completed';
end;
$$;

grant execute on function public.cancel_playdate_as_proposer(uuid) to authenticated;

-- Nudge PostgREST to refresh its schema cache so the new table,
-- functions, and policies are immediately visible to the iOS client
-- without a project restart.
notify pgrst, 'reload schema';
