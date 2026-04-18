-- 015_pet_state.sql
--
-- Persisted virtual-pet stats so that tapping 喂食 / 玩耍 / 摸摸 moves
-- the mood / hunger / energy bars AND the change is visible on every
-- device and every profile screen that renders the pet.
--
-- Up until now, the three stat bars were derived purely from the
-- pet's posts + current time (see `PetStats.derivedHunger /
-- derivedEnergy / decayedMood`).  That was consistent across views
-- but meant feed / play / pet buttons didn't persist — the user
-- reported: "当 I click 喂食/玩耍, nothing happened, the stats did
-- not change".
--
-- Design:
--
-- One row per pet, owner-writable only.  Stores the absolute current
-- stat values plus an `updated_at` timestamp so the client can apply
-- a small in-memory decay while the screen is open without needing
-- to round-trip for every tick.  When a row is missing, the client
-- falls back to the time-derived baseline from `RemotePet+VirtualPet`
-- — this keeps the experience smooth for pets that have never had
-- an owner interaction recorded.
--
-- RLS:
--   * SELECT — everyone.  Non-owners can see the pet's current stats
--     just like they can see the accessory choice.
--   * INSERT / UPDATE — only the pet's owner (via the `pets` FK).
--     This matches the existing accessory write policy from #014 and
--     prevents random visitors from "feeding" someone else's pet.
--
-- The CHECK constraints (0..100) are the same bounds the client
-- enforces; keeping them in the DB means a buggy client build can't
-- leave us with out-of-range values that the renderer can't map.

create table if not exists pet_state (
  pet_id uuid primary key references pets(id) on delete cascade,
  mood int not null default 70 check (mood between 0 and 100),
  hunger int not null default 70 check (hunger between 0 and 100),
  energy int not null default 70 check (energy between 0 and 100),
  updated_at timestamptz not null default now()
);

alter table pet_state enable row level security;

-- SELECT: everyone, including unauthenticated clients for public
-- profile reads.  The stats are not sensitive.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'pet_state'
      and policyname = 'pet_state_select_all'
  ) then
    create policy "pet_state_select_all" on pet_state
      for select
      using (true);
  end if;
end $$;

-- INSERT: only the authenticated owner of the referenced pet.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'pet_state'
      and policyname = 'pet_state_insert_owner'
  ) then
    create policy "pet_state_insert_owner" on pet_state
      for insert
      with check (
        exists (
          select 1 from pets
          where pets.id = pet_id
            and pets.owner_user_id = auth.uid()
        )
      );
  end if;
end $$;

-- UPDATE: same — only the owner.  USING gates which rows the update
-- can target; WITH CHECK gates what values can be written.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'pet_state'
      and policyname = 'pet_state_update_owner'
  ) then
    create policy "pet_state_update_owner" on pet_state
      for update
      using (
        exists (
          select 1 from pets
          where pets.id = pet_id
            and pets.owner_user_id = auth.uid()
        )
      )
      with check (
        exists (
          select 1 from pets
          where pets.id = pet_id
            and pets.owner_user_id = auth.uid()
        )
      );
  end if;
end $$;
