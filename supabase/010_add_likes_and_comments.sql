create table if not exists likes (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint likes_post_user_unique unique (post_id, user_id)
);

create table if not exists comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now()
);

alter table likes enable row level security;
alter table comments enable row level security;

create policy "Anyone can read likes"
on likes for select
using (true);

create policy "Users insert own likes"
on likes for insert
with check (auth.uid() = user_id);

create policy "Users delete own likes"
on likes for delete
using (auth.uid() = user_id);

create policy "Anyone can read comments"
on comments for select
using (true);

create policy "Users insert own comments"
on comments for insert
with check (auth.uid() = user_id);

create policy "Users delete own comments"
on comments for delete
using (auth.uid() = user_id);

create index if not exists idx_likes_post_id on likes(post_id);
create index if not exists idx_likes_user_id on likes(user_id);
create index if not exists idx_comments_post_id on comments(post_id);
create index if not exists idx_comments_user_id on comments(user_id);
create index if not exists idx_comments_created_at on comments(created_at desc);
