# PawPal Social Architecture

## Product Direction

PawPal is evolving from a local-first pet health prototype into a **pet social / pet life app** with WeChat Moments as the primary design reference.

The long-term shape is:
- user accounts
- multiple pets per user
- moments feed
- follow relationships
- local pet care tools
- nearby vets

## Core Decision

Move from single-device local-only identity to a real multi-user app with:
- **Sign in with Apple** for authentication
- **Supabase** for backend/database/storage

This gives:
- iOS-friendly auth
- Postgres data model
- storage for pet images and post images
- row-level security
- simpler iteration than building a backend from scratch

## Recommended Stack

### iOS
- SwiftUI
- SwiftData for temporary local cache/drafts only
- URLSession or Supabase Swift SDK

### Backend Platform
- Supabase
  - Auth
  - Postgres
  - Storage
  - Row Level Security

### Media
- Supabase Storage
  - pet avatars
  - post photos

## Identity Model

Use **user follows user**, not pet follows pet, for the real social graph.

Why:
- simpler mental model
- simpler feed generation
- more standard social architecture
- each user may own multiple pets
- users follow people/accounts; pets are content entities under those users

## Data Model Overview

### users (profile table layered on auth.users)
- id (uuid, same as auth.users.id)
- username
- display_name
- bio
- avatar_url
- created_at

### pets
- id
- owner_user_id
- name
- species
- breed
- age
- weight
- notes
- avatar_url
- created_at
- updated_at

### posts
- id
- owner_user_id
- pet_id
- caption
- mood
- created_at
- updated_at

### post_images
- id
- post_id
- image_url
- sort_order
- created_at

### follows
- id
- follower_user_id
- followed_user_id
- created_at

### likes (later)
- id
- user_id
- post_id
- created_at

### comments (later)
- id
- user_id
- post_id
- body
- created_at

## Feed Logic

Main feed should show:
- posts from the signed-in user
- posts from users the signed-in user follows

Ordered by:
- created_at desc

This can later expand with:
- profile feed
- pet-specific feed
- explore feed

## App Structure

Likely tabs after account migration:
- Moments
- Post
- Pets
- Care
- Me

Possible alternative:
- Home
- Post
- Pets
- Notifications
- Me

For now, `Vets` can remain a dedicated section, but long-term it may live under Care.

## Local-First to Cloud Transition Plan

### Phase 1
Keep current prototype working locally.

### Phase 2
Introduce account/auth:
- Sign in with Apple
- session persistence
- user profile creation

### Phase 3
Move pets/posts to Supabase:
- create remote tables
- upload images to storage
- fetch feed from backend

### Phase 4
Add follows:
- follow/unfollow users
- feed based on follow graph

### Phase 5
Optional social polish:
- likes
- comments
- notifications

## Important Constraints

- Keep the app feeling like a pet life app, not a clinical health app
- Care/health remains a feature, not the whole identity
- Keep UX closer to WeChat Moments than Instagram
- Avoid overbuilding before auth + feed fundamentals work

## Immediate Next Build Steps

1. Finalize database schema
2. Write SQL setup for Supabase
3. Add Sign in with Apple to iOS app
4. Add auth/session state layer
5. Add remote user profile creation
6. Replace local-only post feed with backend-backed feed
