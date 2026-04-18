-- 014_add_pets_accessory.sql
--
-- Adds an `accessory` column to the `pets` table so that the virtual
-- pet's dress-up state (bow / hat / glasses / none) survives between
-- sessions.  Previously the accessory was local SwiftUI `@State` on
-- `VirtualPetView`, so tapping 🎩 and then navigating away reset the
-- pet to bare-headed on the next visit.
--
-- The column is a free-form text so future accessories (e.g. "scarf",
-- "bandana") can be added without another migration.  Values stored by
-- the app today are: 'none', 'bow', 'hat', 'glasses'.  Nil / missing is
-- treated as 'none' by the client for backwards compatibility with rows
-- written before this migration landed.
--
-- Non-owners cannot update other columns on `pets` (RLS from 003), and
-- accessory is no exception — only the pet's owner can change their
-- own pet's outfit.  That's the existing UPDATE policy on `pets`,
-- which we don't need to touch.

alter table pets
  add column if not exists accessory text;

-- Optional constraint: ensure clients only write one of the known
-- accessory values.  Enforced at the DB level so a bad client build
-- can't leave us with arbitrary strings that the renderer can't map.
-- Kept as a CHECK (not an enum) so we can add new values later with a
-- simple `alter table ... drop constraint + add constraint` instead of
-- the more invasive enum migration dance.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'pets_accessory_check'
  ) then
    alter table pets
      add constraint pets_accessory_check
      check (accessory is null or accessory in ('none', 'bow', 'hat', 'glasses'));
  end if;
end $$;
