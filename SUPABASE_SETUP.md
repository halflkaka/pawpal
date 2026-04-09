# Supabase Setup for PetHealth

## Goal

Turn PetHealth from a local-first prototype into a real social app with:
- user accounts
- pets owned by users
- posts
- follows
- image storage

## 1. Create Supabase project

1. Go to `https://supabase.com`
2. Create a new project
3. Pick a project name, for example:
   - `pethealth`
4. Save these values:
   - **Project URL**
   - **Anon Key**
   - **Service Role Key** (server use only, never ship in iOS app)

## 2. Enable authentication

In Supabase Auth settings:
- enable email/password if you want classic login/register
- plan to add **Sign in with Apple** for iOS production

Recommended approach:
- start with email/password for easier dev testing
- add Sign in with Apple after the basic auth flow works

## 3. Run SQL schema

Use the SQL editor in Supabase and run the files in this order:

1. `supabase/001_schema.sql`
2. `supabase/002_indexes.sql`
3. `supabase/003_rls.sql`
4. `supabase/004_storage.sql`
5. `supabase/005_auth_profile_trigger.sql`

Important:
- `005_auth_profile_trigger.sql` is required for reliable signup
- it automatically creates the matching `profiles` row whenever a new auth user is created
- it also backfills any existing auth users who are missing a profile row

## 4. Create storage buckets

The SQL file also documents bucket intent.
You will likely want buckets like:
- `avatars`
- `pet-images`
- `post-images`

## 5. Add iOS app config

You will later need to store in the app:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Do **not** put service role keys in the iOS app.

## 6. First real implementation steps after setup

1. add Supabase Swift SDK
2. add auth/session state
3. create login/register screens
4. create profile row after first sign-in
5. move pets/posts from local-only to Supabase
6. add follow/unfollow users
7. build real moments feed from followed users

## Recommended data model

- users follow users
- users own pets
- posts belong to users and optionally reference a pet

This is simpler and more scalable than pet-follows-pet for a real social platform.

## Product note

PetHealth should now be treated as:
- a pet social / pet life app first
- care tools second

Design reference remains:
- WeChat Moments / 朋友圈
