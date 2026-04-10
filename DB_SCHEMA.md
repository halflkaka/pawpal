# PawPal Database Schema (Proposed)

## Design Rule

- `profiles` = lightweight account identity
- `pets` = rich public social identity

The app should stay pet-first. Human accounts exist for login, ownership, search, and trust. Pets carry most of the expressive public identity.

## 1. profiles

Represents the app-level user account tied to Supabase auth.

```sql
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  display_name text,
  avatar_url text,
  bio text,
  location_text text,
  privacy_level text not null default 'public',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

### Notes
- `email` should stay in Supabase auth, not duplicated in `profiles`
- `username` is the stable searchable identity
- `display_name` is the softer human-facing label
- keep human profiles intentionally lightweight

## 2. pets

```sql
create table pets (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references profiles(id) on delete cascade,
  name text not null,
  avatar_url text,
  species text,
  breed text,
  sex text,
  birthday date,
  age_text text,
  weight text,
  bio text,
  notes text,
  home_city text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

### Notes
- `bio` = public pet intro
- `notes` = owner-facing private or practical notes
- `age_text` supports pets with unknown exact birthday
- pets should be richer than user accounts because they are the visible social actors

## 3. posts

```sql
create table posts (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references profiles(id) on delete cascade,
  pet_id uuid references pets(id) on delete set null,
  caption text not null,
  mood text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

## 4. post_images

```sql
create table post_images (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references posts(id) on delete cascade,
  image_url text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);
```

## 5. follows

```sql
create table follows (
  id uuid primary key default gen_random_uuid(),
  follower_user_id uuid not null references profiles(id) on delete cascade,
  followed_user_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint follows_unique unique (follower_user_id, followed_user_id),
  constraint no_self_follow check (follower_user_id <> followed_user_id)
);
```

## Recommended Indexes

```sql
create index idx_pets_owner_user_id on pets(owner_user_id);
create index idx_posts_owner_user_id on posts(owner_user_id);
create index idx_posts_pet_id on posts(pet_id);
create index idx_posts_created_at on posts(created_at desc);
create index idx_post_images_post_id on post_images(post_id);
create index idx_follows_follower_user_id on follows(follower_user_id);
create index idx_follows_followed_user_id on follows(followed_user_id);
```

## Feed Query Shape

Feed should retrieve posts where:
- owner_user_id is current user
- OR owner_user_id is in users followed by current user

Ordered by:
- created_at desc

## Notes

- Keep pet ownership under users
- Keep social graph between users, not pets
- Likes/comments can be added later once feed/auth is stable
