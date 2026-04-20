-- 020_fix_stories_owner_fk.sql
-- Date: 2026-04-18
--
-- Re-point `stories.owner_user_id` FK from `auth.users(id)` → `profiles(id)`
-- so PostgREST can expose the relationship via the REST API.
--
-- Why this was broken:
--
--   Migration 018 declared the FK as `references auth.users(id)`.
--   PostgREST only resolves embedded-resource joins (the
--   `profiles!owner_user_id(*)` syntax used by `StoryService`) against
--   tables in schemas it has been configured to expose — typically
--   `public`. The `auth` schema is intentionally hidden, so from
--   PostgREST's view, `stories` had no FK to any visible table that
--   would resolve to `profiles`. Queries that tried to embed
--   `profiles` as a joined resource failed with
--   "could not find relationship between stories and profiles in the
--    schema cache".
--
--   Every other owner-bearing table in the schema (`pets.owner_user_id`,
--   `posts.owner_user_id`, `follows.follower_user_id` /
--   `followed_user_id`) already references `profiles(id)`, which itself
--   references `auth.users(id)` — so profiles is effectively a 1:1
--   projection of the auth user table that PostgREST *can* see. Pointing
--   the stories FK at `profiles(id)` instead of `auth.users(id)` makes
--   stories follow the same pattern, with identical semantics (a user
--   can't have a profile without an auth row, so the cascade chain is
--   preserved: delete auth.users → cascade to profiles → cascade to
--   stories).
--
-- Safe to re-run:
--
--   * The drop is gated on `if exists` so a database that was created
--     after this migration (with the FK already pointing at profiles)
--     won't error.
--   * The add is gated on a `pg_constraint` lookup so the second run
--     is a no-op.
--   * No row migration is required — `owner_user_id` values are the
--     same auth uid either way, and profiles ids are 1:1 with
--     auth.users ids by the schema's own design.

-- Drop the inline FK from 018. Postgres auto-names inline FKs as
-- `{table}_{column}_fkey`, so this is the auto-generated name.
alter table public.stories
  drop constraint if exists stories_owner_user_id_fkey;

-- Add the new FK pointing at profiles. Named explicitly so future
-- re-runs can find and skip it.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'stories_owner_user_id_fkey'
      and conrelid = 'public.stories'::regclass
  ) then
    alter table public.stories
      add constraint stories_owner_user_id_fkey
      foreign key (owner_user_id)
      references public.profiles(id)
      on delete cascade;
  end if;
end $$;

-- Nudge PostgREST to rebuild its schema cache immediately rather than
-- waiting for the next periodic refresh. Without this, the API will
-- keep reporting "could not find relationship" until the cache rolls
-- over (usually ~10 minutes on managed Supabase).
notify pgrst, 'reload schema';
