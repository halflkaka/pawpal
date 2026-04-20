-- 023_playdates.sql
-- Date: 2026-04-18
--
-- Playdates — flagship pet-to-pet primitive. See
-- docs/sessions/2026-04-18-pm-direction-playdates.md for product scope
-- and docs/sessions/2026-04-18-pm-playdates-mvp-execution.md for this
-- migration's place in the execution plan.
--
-- This is the FIRST pet-to-pet graph edge in the schema. The follow
-- graph stays user-to-user (see docs/decisions.md); playdates model the
-- pet-to-pet relationship directly via proposer_pet_id / invitee_pet_id.
-- user_id columns are denormalised onto the row so RLS checks don't
-- need a pets join on every query.
--
-- Shape:
--
--   * `pets.open_to_playdates` — visibility gate, default **true**
--     (flipped from `false` on 2026-04-19 for lower onboarding
--     friction). A BEFORE INSERT trigger enforces that the invitee
--     pet has this column set to true; RLS `with check` can't cleanly
--     express the cross-table lookup so we reach for a trigger. The
--     iOS 约遛弯 pill also gates visibility on this flag — the trigger
--     is defense-in-depth. Owners can toggle the flag off in the pet
--     editor; the INSERT trigger still protects invitees from stale
--     UI states where the composer opened before the toggle flipped.
--
--   * `playdates` — one row per invitation. status transitions:
--     proposed → accepted | declined | cancelled, accepted →
--     cancelled | completed. The CHECK constraint enforces the
--     enum; no-self-playdate CHECK blocks the degenerate
--     proposer==invitee case.
--
--   * RLS — airtight. Strangers see nothing pre-acceptance; the
--     invitee and proposer each see their own rows. Both sides can
--     UPDATE (status transitions) and DELETE (GDPR). Only the proposer
--     can INSERT, and only against their own pet.
--
--   * Notification trigger — AFTER INSERT calls `queue_notification`
--     from migration 022 with type `playdate_invited`. The edge
--     function owns the APNs path; the three device-scheduled
--     `playdate_t_*` reminders stay on the local-notifications path.
--
-- Prerequisites: migration 022 must have been applied (for
-- `queue_notification`). Idempotent and safe to re-apply.

-- ---------------------------------------------------------------------
-- pets.open_to_playdates — opt-in gate
-- ---------------------------------------------------------------------
-- Default changed from `false` → `true` on 2026-04-19. See
-- docs/decisions.md → "Playdates are opt-out (default on); toggle
-- still governs visibility". A pet created after migration 023
-- applies is automatically visible to 约遛弯 invitations; the owner
-- can toggle off in the pet editor.
alter table public.pets
  add column if not exists open_to_playdates boolean not null default true;

-- ---------------------------------------------------------------------
-- playdates
-- ---------------------------------------------------------------------
create table if not exists public.playdates (
  id uuid primary key default gen_random_uuid(),
  proposer_pet_id  uuid not null references public.pets(id)     on delete cascade,
  invitee_pet_id   uuid not null references public.pets(id)     on delete cascade,
  proposer_user_id uuid not null references public.profiles(id) on delete cascade,
  invitee_user_id  uuid not null references public.profiles(id) on delete cascade,
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

create index if not exists playdates_invitee_status_idx
  on public.playdates(invitee_user_id, status);
create index if not exists playdates_proposer_status_idx
  on public.playdates(proposer_user_id, status);
create index if not exists playdates_scheduled_at_idx
  on public.playdates(scheduled_at);

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------
--
-- SELECT: either side of the row can read it — stranger visibility is
--         zero pre-acceptance because a stranger isn't on either side
--         of the row.
-- INSERT: auth'd user must be the proposer AND own the proposer pet.
-- UPDATE: either side can update (status transitions).
-- DELETE: either side can hard-delete (account-deletion / GDPR path).
--
-- The BEFORE INSERT trigger below layers on an extra check that the
-- invitee pet is open_to_playdates — RLS alone can't express that
-- without an EXISTS subquery that's awkward to maintain.

alter table public.playdates enable row level security;

drop policy if exists "playdates_select_participants" on public.playdates;
create policy "playdates_select_participants" on public.playdates
  for select
  using (auth.uid() = proposer_user_id or auth.uid() = invitee_user_id);

drop policy if exists "playdates_insert_proposer" on public.playdates;
create policy "playdates_insert_proposer" on public.playdates
  for insert
  with check (
    auth.uid() = proposer_user_id
    and exists (
      select 1 from public.pets
      where id = proposer_pet_id and owner_user_id = auth.uid()
    )
  );

drop policy if exists "playdates_update_participants" on public.playdates;
create policy "playdates_update_participants" on public.playdates
  for update
  using (auth.uid() = proposer_user_id or auth.uid() = invitee_user_id)
  with check (auth.uid() = proposer_user_id or auth.uid() = invitee_user_id);

drop policy if exists "playdates_delete_participants" on public.playdates;
create policy "playdates_delete_participants" on public.playdates
  for delete
  using (auth.uid() = proposer_user_id or auth.uid() = invitee_user_id);

-- ---------------------------------------------------------------------
-- open-to-playdates gate — BEFORE INSERT trigger
-- ---------------------------------------------------------------------
--
-- Reads `pets.open_to_playdates` for the invitee and rejects the insert
-- with a readable `hint` when the flag is false. SECURITY DEFINER so
-- the check can read `pets` regardless of the caller's RLS scope (the
-- select-own-pet-only policy would hide the row otherwise and the
-- gate would spuriously fail closed).

create or replace function public.playdates_gate_invitee_open()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _open boolean;
begin
  select open_to_playdates into _open from public.pets where id = new.invitee_pet_id;
  if _open is not true then
    raise exception 'invitee_pet_not_open_to_playdates'
      using hint = '该毛孩子的主人没有开启遛弯邀请';
  end if;
  return new;
end;
$$;

drop trigger if exists playdates_gate_before_insert on public.playdates;
create trigger playdates_gate_before_insert
  before insert on public.playdates
  for each row execute function public.playdates_gate_invitee_open();

-- ---------------------------------------------------------------------
-- notify trigger — reuses migration 022's queue_notification
-- ---------------------------------------------------------------------
--
-- `playdate_invited` is already in the migration 022 `notifications.type`
-- check constraint — this trigger just enqueues a row; the edge
-- function's `playdate_invited` branch owns the APNs payload.

create or replace function public.playdates_notify_invited()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.queue_notification(
    new.invitee_user_id,     -- recipient
    new.proposer_user_id,    -- actor
    'playdate_invited',
    new.id                   -- target = playdate id
  );
  return new;
end;
$$;

drop trigger if exists playdates_notify_after_insert on public.playdates;
create trigger playdates_notify_after_insert
  after insert on public.playdates
  for each row execute function public.playdates_notify_invited();

-- Nudge PostgREST to refresh its schema cache so the new table is
-- immediately visible to the iOS client without a project restart.
notify pgrst, 'reload schema';
