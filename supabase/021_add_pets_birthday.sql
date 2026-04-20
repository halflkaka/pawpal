-- Some older installs were provisioned before `birthday` was added to the
-- canonical 001 schema (see the note in 006_pets_age_column_alignment.sql).
-- The Swift `RemotePet` model now expects this column to exist for the
-- milestones MVP (birthday card on Feed + 即将到来的纪念日 rail on
-- PetProfileView), so backfill it conditionally on any install that's
-- missing it. Safe to re-run: `add column if not exists` is a no-op when
-- the column is already present.

alter table pets
  add column if not exists birthday date;

-- Tell PostgREST to refresh its schema cache so the new column is
-- immediately visible to the iOS client without a project restart.
notify pgrst, 'reload schema';
