-- Align live pets table with current app fields.
-- Add bio if missing. Drop notes because pet notes are no longer used by the app.

alter table pets
  add column if not exists bio text;

alter table pets
  drop column if exists notes;
