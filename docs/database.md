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

### pet_visits
Social proof for `PetProfileView`. Records one row per unique (pet, viewer, calendar day). See migration `013_pet_visits_and_boops.sql` and CHANGELOG #38.

```sql
create table pet_visits (
  pet_id uuid not null references pets(id) on delete cascade,
  viewer_user_id uuid not null references auth.users(id) on delete cascade,
  visited_on date not null default (now() at time zone 'utc')::date,
  first_visited_at timestamptz not null default now(),
  primary key (pet_id, viewer_user_id, visited_on)
);
```

- The primary key is the dedupe key — `INSERT ... ON CONFLICT DO NOTHING` on the client means same-day refreshes don't double-count, but returning on a new calendar day adds a new row.
- **Owner self-visits are filtered client-side** (the app skips `recordVisit` when `viewer_user_id == pet.owner_user_id`). This is deliberate — keeping the exclusion in app code rather than the RLS policy lets an admin backfill or correct the table without fighting policies.
- Displayed on `PetProfileView` stats card as "访客" with the count being `COUNT(*)` for the pet.

---

### pets.boop_count (column)
Cumulative tap-to-boop counter on the virtual pet. Added in migration 013.

```sql
alter table pets
  add column boop_count integer not null default 0;
```

Updated only via the `increment_pet_boop_count` RPC, never via direct `UPDATE` from the client (to avoid having to loosen the `pets` RLS update policy for non-owners). The RPC is `security definer` and `grant execute ... to authenticated` — any signed-in user can boop any pet.

```sql
create function increment_pet_boop_count(
  pet_id uuid,
  by_count integer default 1
) returns integer
  language plpgsql
  security definer
  set search_path = public;
```

Displayed on `PetProfileView` stats card as "摸摸". The client debounces taps over ~1.8s and flushes an aggregate delta, so a burst of 10 taps becomes one RPC call with `by_count = 10`.

---

### pets.accessory (column)
Persisted virtual-pet dress-up state. Added in migration 014 / CHANGELOG #39.

```sql
alter table pets
  add column accessory text;

alter table pets
  add constraint pets_accessory_check
  check (accessory is null or accessory in ('none', 'bow', 'hat', 'glasses'));
```

Written by owners only (the existing `pets` UPDATE RLS policy restricts UPDATEs to `owner_user_id = auth.uid()`). The CHECK constraint rejects unknown values so a bad client build can't leave us with arbitrary strings the renderer can't map to `DogAvatar.Accessory`. Nil / missing is treated as `'none'` by the client for rows written before the migration landed.

Read inside `RemotePet.virtualPetState(stats:posts:now:)` — when the virtual pet stage mounts, the saved accessory is rendered immediately instead of resetting to bare-headed.

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
create index idx_pet_visits_pet_id on pet_visits(pet_id);
create index idx_pet_visits_viewer_user_id on pet_visits(viewer_user_id);
create index idx_pet_visits_visited_on on pet_visits(visited_on desc);
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
