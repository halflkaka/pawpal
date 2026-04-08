alter table profiles enable row level security;
alter table pets enable row level security;
alter table posts enable row level security;
alter table post_images enable row level security;
alter table follows enable row level security;

-- profiles
create policy "profiles are publicly readable"
on profiles for select
using (true);

create policy "users can insert own profile"
on profiles for insert
with check (auth.uid() = id);

create policy "users can update own profile"
on profiles for update
using (auth.uid() = id);

-- pets
create policy "pets are publicly readable"
on pets for select
using (true);

create policy "users can insert own pets"
on pets for insert
with check (auth.uid() = owner_user_id);

create policy "users can update own pets"
on pets for update
using (auth.uid() = owner_user_id);

create policy "users can delete own pets"
on pets for delete
using (auth.uid() = owner_user_id);

-- posts
create policy "posts are publicly readable"
on posts for select
using (true);

create policy "users can insert own posts"
on posts for insert
with check (auth.uid() = owner_user_id);

create policy "users can update own posts"
on posts for update
using (auth.uid() = owner_user_id);

create policy "users can delete own posts"
on posts for delete
using (auth.uid() = owner_user_id);

-- post_images
create policy "post images are publicly readable"
on post_images for select
using (true);

create policy "users can insert images for own posts"
on post_images for insert
with check (
  exists (
    select 1 from posts
    where posts.id = post_images.post_id
    and posts.owner_user_id = auth.uid()
  )
);

create policy "users can update images for own posts"
on post_images for update
using (
  exists (
    select 1 from posts
    where posts.id = post_images.post_id
    and posts.owner_user_id = auth.uid()
  )
);

create policy "users can delete images for own posts"
on post_images for delete
using (
  exists (
    select 1 from posts
    where posts.id = post_images.post_id
    and posts.owner_user_id = auth.uid()
  )
);

-- follows
create policy "follows are publicly readable"
on follows for select
using (true);

create policy "users can insert own follows"
on follows for insert
with check (auth.uid() = follower_user_id);

create policy "users can delete own follows"
on follows for delete
using (auth.uid() = follower_user_id);
