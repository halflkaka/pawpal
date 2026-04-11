# PawPal

A playful iPhone-first pet social app built in SwiftUI.

## What it does today

PawPal already includes a working social app core:
- email sign in and registration with Supabase Auth
- profile editing
- pet add, edit, delete, and active-pet selection
- feed loading from Supabase
- create-post flow with pet selection and image upload
- likes and comments
- warm Chinese-first SwiftUI UI across the main screens

Some areas are still in progress:
- discovery is still partly demo/static
- chat is still mostly a shell
- deeper pet profile pages and follow systems are not finished yet

## Structure

- `PawPal/` — iOS SwiftUI app
- `PawPalTests/` — test target
- `PawPal.xcodeproj/` — Xcode project
- `supabase/` — SQL migrations / backend setup files
- `pet-health-backend/` — legacy backend from the earlier health-app phase

## Requirements

To run locally, you should have:
- macOS with Xcode 16+
- iOS Simulator support installed
- a Supabase project
- a bucket for post images

## Local setup

### 1. Clone and open

```bash
git clone https://github.com/halflkaka/pawpal.git
cd pawpal
open PawPal.xcodeproj
```

Then build the `PawPal` scheme in Xcode.

### 2. Create a Supabase project

Create a new Supabase project at <https://supabase.com>.

You will need:
- Project URL
- Anon key

### 3. Apply the database setup

This repo includes Supabase migration/setup files under `supabase/`.

Set up your database by applying the SQL there in order, using either:
- the Supabase SQL editor, or
- the Supabase CLI if you prefer local migration workflows

At minimum, your Supabase project needs these app features working:
- `profiles`
- `pets`
- `posts`
- `post_images`
- `likes`
- `comments`
- the related RLS policies
- storage for post images

If your schema is incomplete, some app surfaces may still load with fallback behavior, but posting, comments, or profile-linked features may be missing or partially degraded.

### 4. Create the storage bucket

Create a public storage bucket named:

```text
post-images
```

The app uploads post photos there.

### 5. Add your Supabase config in Xcode

The app expects a local `SupabaseConfig.swift` with your project credentials.

If it does not already exist in your checkout, create:

```text
PawPal/SupabaseConfig.swift
```

with something like:

```swift
import Foundation

enum SupabaseConfig {
    static let urlString = "https://YOUR_PROJECT.supabase.co"
    static let anonKey = "YOUR_SUPABASE_ANON_KEY"
}
```

Do not commit your personal keys.

### 6. Run the app

Use an iPhone simulator, for example:
- iPhone 16

Then:
- register a new account
- create your profile
- add a pet
- create a post
- test likes and comments

## Development notes

- Main UI is SwiftUI-native and iPhone-first
- Current design direction uses warm cream backgrounds, rounded white cards, soft orange accents, and a playful pet-social tone
- The app currently prefers graceful fallback behavior when some optional Supabase tables are not fully available yet
- The legacy `pet-health-backend/` folder is not needed for the current PawPal iOS app flow

## Troubleshooting

### Build fails because Supabase config is missing

Make sure `PawPal/SupabaseConfig.swift` exists and contains a valid URL and anon key.

### App launches but login or feed does not work

Check:
- Supabase URL / anon key are correct
- the SQL schema has been applied
- RLS policies are present
- your storage bucket `post-images` exists

### Images do not appear after posting

Check:
- `post-images` bucket exists
- storage policies allow upload/read for your test flow
- `post_images` table exists and is linked correctly

## Current direction

PawPal is being refactored from a pet-health utility into a warm, social pet product with:
- a home feed for pet moments
- explore surfaces for pets, tags, and places
- chat-style messaging screens
- a share/create post flow
- richer pet profile experiences

## Status

The app shell has been renamed to PawPal and the main SwiftUI surfaces are actively being updated toward the new pet-social experience.
