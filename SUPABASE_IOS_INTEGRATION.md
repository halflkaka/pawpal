# Supabase iOS Integration

## Current State

The app already has auth/session scaffolding in place:
- `AuthManager`
- `AuthView`
- `MainTabView`
- `SupabaseConfig`

The next step is adding the real Supabase Swift package in Xcode.

## Add Supabase Swift SDK in Xcode

1. Open `PawPal.xcodeproj` in Xcode
2. Select the blue project icon
3. Select the `PawPal` project
4. Open the **Package Dependencies** tab
5. Click the **+** button
6. Use this URL:
   - `https://github.com/supabase/supabase-swift.git`
7. Choose a recent stable version, preferably latest 2.x
8. Add the package to the `PawPal` target

## After package install

The app can import:
- `Supabase`

## Planned wiring

`AuthManager` should:
- create a Supabase client
- sign in with email/password
- sign up with email/password
- restore session if available
- sign out
- create/load a `profiles` row

## Important

Use only:
- project URL
- anon key

Never put the service role key in the iOS app.
