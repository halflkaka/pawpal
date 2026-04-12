-- Storage policies for image uploads used by PawPal/Services/PostsService.swift
-- App upload path: {user_id}/{post_id}/{index}.jpg in bucket `post-images`

insert into storage.buckets (id, name, public)
values ('post-images', 'post-images', true)
on conflict (id) do update
set public = excluded.public;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Public can read post-images'
  ) then
    create policy "Public can read post-images"
    on storage.objects for select
    using (bucket_id = 'post-images');
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Authenticated users can upload post-images'
  ) then
    create policy "Authenticated users can upload post-images"
    on storage.objects for insert
    to authenticated
    with check (
      bucket_id = 'post-images'
      and owner = auth.uid()
    );
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Authenticated users can update own post-images'
  ) then
    create policy "Authenticated users can update own post-images"
    on storage.objects for update
    to authenticated
    using (
      bucket_id = 'post-images'
      and owner = auth.uid()
    )
    with check (bucket_id = 'post-images');
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Authenticated users can delete own post-images'
  ) then
    create policy "Authenticated users can delete own post-images"
    on storage.objects for delete
    to authenticated
    using (
      bucket_id = 'post-images'
      and owner = auth.uid()
    );
  end if;
end $$;
