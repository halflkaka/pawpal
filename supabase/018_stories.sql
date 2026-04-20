-- 018_stories.sql
-- Date: 2026-04-18
--
-- 24-hour "stories" for pets — the ephemeral-media surface that lives
-- above the feed rail. A pet owner can post one image (or video, once
-- we wire up the upload pipeline) that expires 24 hours after creation.
-- Followers (and visitors who happen on the pet) see an unread ring on
-- the pet's avatar in the home rail until the story either expires or
-- they tap through.
--
-- Scope (MVP):
--   * Image-first. The `media_type` column accepts 'video' so a later
--     PR can enable video uploads without a schema migration, but the
--     client only exposes the image path for now.
--   * Per-pet, not per-user. A user with three pets can post one story
--     per pet — each pet's rail ring is independent. This mirrors the
--     rest of the app where pets are the protagonist of the feed, not
--     the human owner (see product.md "pets-as-protagonists").
--   * No read-receipts / view counts in this migration. Add a
--     `story_views` table in a follow-up when we need "seen by" UX.
--
-- Design:
--
-- One row per story. `expires_at` is set by default to `now() + 24h`
-- at insert time and is the sole filter for "active" — we do NOT need
-- a cleanup cron for MVP because every SELECT path filters with
-- `expires_at > now()`. Old rows still in the table are harmless and
-- can be bulk-deleted manually or via a scheduled job later.
--
-- Two indexes:
--   * `(pet_id, expires_at desc)` — the "active story for this pet"
--     lookup used by the rail ring and the pet profile page.
--   * `(owner_user_id, expires_at desc)` — supports "my own stories"
--     lists (deletion UI, own-profile ring).
--
-- Storage: create a `story-media` bucket MANUALLY in the Supabase
-- dashboard (public read, authenticated write). Same pattern as
-- `post-images` — we don't create buckets from SQL because the CLI
-- config is the source of truth for bucket policies.
--
-- RLS:
--   * SELECT — any authenticated user, but only rows whose
--     `expires_at > now()`. Expired rows are invisible to the client
--     even without a cleanup job.
--   * INSERT — the authenticated user inserting themselves as
--     `owner_user_id`, AND only if the referenced pet belongs to that
--     same user (prevents A from posting a story "as" B's pet).
--   * DELETE — owner only.
--   * UPDATE — no policy; stories are immutable. Edits would fight
--     the feed's ephemeral model, and there's no obvious UX for it.

create table if not exists public.stories (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  pet_id uuid not null references public.pets(id) on delete cascade,
  media_url text not null,
  media_type text not null default 'image' check (media_type in ('image','video')),
  caption text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours')
);

create index if not exists stories_pet_id_idx on public.stories(pet_id, expires_at desc);
create index if not exists stories_owner_id_idx on public.stories(owner_user_id, expires_at desc);

alter table public.stories enable row level security;

-- SELECT: any authenticated user can read a story whose window is still
-- open. Expired stories are filtered at the DB level so a stale client
-- can't resurface them.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'stories'
      and policyname = 'stories_select_active'
  ) then
    create policy "stories_select_active" on public.stories
      for select
      using (
        auth.uid() is not null
        and expires_at > now()
      );
  end if;
end $$;

-- INSERT: the caller must be authenticated, must be inserting
-- themselves as the owner, AND must own the referenced pet. The pet
-- ownership check closes the "A posts as B's pet" hole — without it,
-- A could satisfy `owner_user_id = auth.uid()` while setting
-- `pet_id` to any pet in the table.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'stories'
      and policyname = 'stories_insert_owner'
  ) then
    create policy "stories_insert_owner" on public.stories
      for insert
      with check (
        owner_user_id = auth.uid()
        and exists (
          select 1 from public.pets
          where pets.id = pet_id
            and pets.owner_user_id = auth.uid()
        )
      );
  end if;
end $$;

-- DELETE: the owner can remove their own story at any time. The
-- ephemeral model already handles expiry, so this is mostly for the
-- "posted something embarrassing, pull it down" flow.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'stories'
      and policyname = 'stories_delete_owner'
  ) then
    create policy "stories_delete_owner" on public.stories
      for delete
      using (owner_user_id = auth.uid());
  end if;
end $$;

-- No UPDATE policy — stories are immutable. Re-post instead of edit.
