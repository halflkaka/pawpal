-- 019_add_story_media_storage.sql
-- Date: 2026-04-18
--
-- Creates the `story-media` Supabase Storage bucket + RLS policies that
-- back the 24h ephemeral stories surface (migration 018 + StoryService).
--
-- Migration 018 intentionally deferred bucket creation to "manual via the
-- dashboard" so the CLI bucket policies could be the source of truth
-- (matching the post-images flow). In practice nobody clicked the button,
-- and every `StoryService.postStory` upload fails with "Bucket not found"
-- in the composer's inline error row. This migration codifies the bucket
-- so a fresh Supabase project is uploadable out of the box.
--
-- Mirrors `012_add_post_images_storage_policies.sql` exactly:
--   * Public read (story-media URLs are embedded in app screens just like
--     post images; ephemeral expiry is enforced at the row level by
--     `expires_at`, not at the storage layer).
--   * Authenticated insert/update/delete, gated by `owner = auth.uid()`
--     so a user can only manage objects they uploaded.
--
-- Storage path layout (set by StoryService.postStory):
--   {owner_user_id}/{story_id}.{jpg|mp4}
--
-- Note: the bucket is created via `insert into storage.buckets` (the
-- documented SQL path). `on conflict do update` keeps the migration
-- idempotent — re-running won't error if the bucket was already created
-- through the dashboard.

insert into storage.buckets (id, name, public)
values ('story-media', 'story-media', true)
on conflict (id) do update
set public = excluded.public;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Public can read story-media'
  ) then
    create policy "Public can read story-media"
    on storage.objects for select
    using (bucket_id = 'story-media');
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Authenticated users can upload story-media'
  ) then
    create policy "Authenticated users can upload story-media"
    on storage.objects for insert
    to authenticated
    with check (
      bucket_id = 'story-media'
      and owner = auth.uid()
    );
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Authenticated users can update own story-media'
  ) then
    create policy "Authenticated users can update own story-media"
    on storage.objects for update
    to authenticated
    using (
      bucket_id = 'story-media'
      and owner = auth.uid()
    )
    with check (bucket_id = 'story-media');
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Authenticated users can delete own story-media'
  ) then
    create policy "Authenticated users can delete own story-media"
    on storage.objects for delete
    to authenticated
    using (
      bucket_id = 'story-media'
      and owner = auth.uid()
    );
  end if;
end $$;
