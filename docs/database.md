# Database Guide

PawPal uses Supabase (PostgreSQL) as its backend. This guide covers the design philosophy, table structure, and key decisions to keep in mind when making schema changes.

---

## Design Philosophy

**Profiles are lightweight. Pets are the social actors.**

- `profiles` = account identity tied to Supabase auth (login, ownership, search)
- `pets` = rich public social identity (the visible presence in the feed)

Keep human profiles intentionally lean. Pets carry most of the expressive content — bio, breed, personality, photos. When in doubt, put social attributes on `pets`, not `profiles`.

**Social graph connects users, not pets.**

Follows are between user accounts (`follower_user_id → followed_user_id`). This keeps feed queries simple and avoids a complex pet-to-pet relationship layer.

---

## Tables

### profiles
Represents the app-level user account, tied to Supabase auth.

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

- `username` is the stable, searchable identity
- `display_name` is the softer human-facing label
- `email` stays in Supabase auth — do not duplicate it here

---

### pets
The primary social actor. Richer than profiles by design.

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

- `bio` is public-facing
- `notes` is owner-facing (private or practical)
- `age_text` supports pets with unknown exact birthdays

---

### posts
Content shared by users, linked to a pet.

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

- `pet_id` is nullable — if the pet is deleted, posts are preserved with `set null`

---

### post_images
Images attached to a post, ordered by position.

```sql
create table post_images (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references posts(id) on delete cascade,
  image_url text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);
```

---

### follows
Social graph between user accounts.

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

---

## Indexes

```sql
create index idx_pets_owner_user_id on pets(owner_user_id);
create index idx_posts_owner_user_id on posts(owner_user_id);
create index idx_posts_pet_id on posts(pet_id);
create index idx_posts_created_at on posts(created_at desc);
create index idx_post_images_post_id on post_images(post_id);
create index idx_follows_follower_user_id on follows(follower_user_id);
create index idx_follows_followed_user_id on follows(followed_user_id);
```

---

## Feed Query Shape

The home feed retrieves posts where:
- `owner_user_id` is the current user, **or**
- `owner_user_id` is someone the current user follows

Ordered by `created_at desc`.

---

## Adding or Changing Tables

- Add new SQL files under `supabase/` with a numeric prefix (e.g. `012_add_tags.sql`)
- Apply in order — migrations are cumulative
- Update this doc if the schema or design philosophy changes
- Never modify existing migration files — add a new one instead
