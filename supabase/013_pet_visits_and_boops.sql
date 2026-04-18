-- 013_pet_visits_and_boops.sql
--
-- Adds the social-engagement primitives backing CHANGELOG #38:
--
--   * pet_visits table: one row per (pet, viewer, calendar day). Lets us
--     display a "Unique visits per day" tracker on PetProfileView without
--     double-counting refreshes within the same day.
--
--   * pets.boop_count column: cheap denormalized counter incremented by
--     the `increment_pet_boop_count` RPC whenever a visitor taps the
--     virtual pet. Stored on the pet row so we can render it inline in
--     the stats card without a second SELECT.
--
-- Owner self-visits are filtered *client-side* (the app skips the
-- recordVisit call when viewer_user_id == owner_user_id). Keeping that
-- check in app code rather than a RLS policy lets an admin backfill or
-- correct the table without having to disable policies first.

-- -----------------------------------------------------------------------
-- pet_visits
-- -----------------------------------------------------------------------

create table if not exists pet_visits (
  pet_id uuid not null references pets(id) on delete cascade,
  viewer_user_id uuid not null references auth.users(id) on delete cascade,
  visited_on date not null default (now() at time zone 'utc')::date,
  first_visited_at timestamptz not null default now(),
  primary key (pet_id, viewer_user_id, visited_on)
);

create index if not exists idx_pet_visits_pet_id on pet_visits(pet_id);
create index if not exists idx_pet_visits_viewer_user_id on pet_visits(viewer_user_id);
create index if not exists idx_pet_visits_visited_on on pet_visits(visited_on desc);

alter table pet_visits enable row level security;

-- Anyone can read visit totals — pet profiles are public.
create policy "Anyone can read pet_visits"
on pet_visits for select
using (true);

-- A user can only record a visit as themselves.
create policy "Users insert own pet_visits"
on pet_visits for insert
with check (auth.uid() = viewer_user_id);

-- -----------------------------------------------------------------------
-- pets.boop_count
-- -----------------------------------------------------------------------

alter table pets
  add column if not exists boop_count integer not null default 0;

-- -----------------------------------------------------------------------
-- increment_pet_boop_count RPC
-- -----------------------------------------------------------------------
--
-- Called by `PetsService.incrementBoopCount(for:by:)` after the client
-- has debounced a burst of taps. Takes an integer delta so a burst of
-- 12 taps inside the 2s debounce window becomes one RPC call with
-- by_count = 12 instead of 12 separate calls.
--
-- Uses security definer so RLS on `pets` (which only allows the owner
-- to update their own row) doesn't block visitor boops. The RPC
-- intentionally *only* updates boop_count — no other columns — so it's
-- safe to expose broadly.

create or replace function increment_pet_boop_count(
  pet_id uuid,
  by_count integer default 1
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  new_count integer;
begin
  if by_count is null or by_count <= 0 then
    -- No-op: guards against negative deltas and wasted writes.
    select boop_count into new_count from pets where id = pet_id;
    return coalesce(new_count, 0);
  end if;

  update pets
    set boop_count = boop_count + by_count
    where id = pet_id
    returning boop_count into new_count;

  return coalesce(new_count, 0);
end;
$$;

-- Allow authenticated users (i.e. any signed-in visitor) to call the RPC.
grant execute on function increment_pet_boop_count(uuid, integer) to authenticated;
