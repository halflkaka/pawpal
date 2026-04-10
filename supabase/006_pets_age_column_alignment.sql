-- Align legacy installs with current iOS pet payloads.
-- Canonical column stays age_text for now.
-- Keep this migration minimal because some older installs do not have birthday.

alter table pets
  add column if not exists age_text text;
