# 🐾 PawPal

A warm, social iPhone app for pet lovers. Share moments, discover other pets, and build a community around the animals you love.

---

## ✨ What it does

- 📸 **Feed** — scroll through pet moments from people you follow
- 🐶 **Pet profiles** — add your pets with photos, breed, bio, and personality
- ✍️ **Create posts** — share photos, pick a mood, tag your pet
- ❤️ **Likes & comments** — react to and discuss posts
- 🔍 **Discover** — explore pets, places, and trending spots
- 💬 **Chat** — message other pet owners *(in progress)*

---

## 🏗 Tech stack

| Layer | Technology |
|---|---|
| iOS app | Swift, SwiftUI |
| Backend | Supabase (PostgreSQL, Auth, Storage) |
| Design | Custom design system — warm cream, orange accents, rounded components |

---

## 🚀 Getting started

### 1. Clone and open

```bash
git clone https://github.com/halflkaka/pawpal.git
cd pawpal
open PawPal.xcodeproj
```

Select an iPhone simulator (iPhone 16 or later) and hit ⌘R.

### 2. Set up Supabase

Create a free project at [supabase.com](https://supabase.com). You'll need the **Project URL** and **Anon key**.

Apply the SQL migrations in `supabase/` in order using the Supabase SQL editor.

Your project needs these tables: `profiles`, `pets`, `posts`, `post_images`, `likes`, `comments`, `follows` — plus a public storage bucket named `post-images`.

### 3. Add your config

Create `PawPal/SupabaseConfig.swift`:

```swift
enum SupabaseConfig {
    static let urlString = "https://YOUR_PROJECT.supabase.co"
    static let anonKey = "YOUR_ANON_KEY"
}
```

Do not commit this file.

### 4. Run

Build and run in Xcode. Register an account, add a pet, and create a post.

---

## 🗂 Project structure

```
PawPal/
├── Models/
│   ├── AppUser.swift                  # Authenticated user session
│   ├── RemotePost.swift               # Post with images, likes, comments
│   ├── RemotePet.swift                # Pet profile data
│   ├── RemoteComment.swift            # Comment with author info
│   └── PostDraft.swift                # Draft post state
├── Services/
│   ├── AuthService.swift              # Auth protocol + Supabase implementation
│   ├── AuthManager.swift              # Auth state manager (@Observable)
│   ├── PostsService.swift             # Feed loading, post creation, likes, comments
│   ├── PetsService.swift              # Pet CRUD
│   ├── ProfileService.swift           # Profile loading and upserting
│   ├── FollowService.swift            # Follow/unfollow, follower counts
│   └── SupabaseConfig.swift           # Project URL and anon key (not committed)
├── Views/
│   ├── PawPalDesignSystem.swift       # Design tokens, colors, reusable components
│   ├── ContentView.swift              # Root auth state router
│   ├── MainTabView.swift              # 5-tab navigation shell
│   ├── FeedView.swift                 # Home feed with post cards
│   ├── CreatePostView.swift           # Post creation flow
│   ├── ProfileView.swift              # User profile, pet management, post grid
│   ├── ContactsView.swift             # Discover screen
│   ├── CommentsView.swift             # Comments sheet
│   ├── AuthView.swift                 # Login and registration
│   └── ChatListView.swift             # Chat list (in progress)
├── Storage/
│   └── SwiftDataModels.swift          # Local models (unused — Supabase is source of truth)
└── PawPalApp.swift                    # App entry point

PawPalTests/
└── PawPalTests.swift                  # Unit tests (models, validation logic)

PawPalUITests/
├── PawPalUITests.swift                # UI tests (launch, critical flows)
└── PawPalUITestsLaunchTests.swift     # Launch performance baseline

supabase/
├── 001_schema.sql                     # Core tables
├── 002_indexes.sql                    # Query indexes
├── 003_rls.sql                        # Row-level security policies
├── 004_storage.sql                    # Storage bucket setup
├── 005_auth_profile_trigger.sql       # Auto-create profile on signup
└── 006–011_*.sql                      # Incremental schema migrations

docs/
├── database.md                        # Schema design and table guide
├── pr-template.md                     # PR description standard
├── testing.md                         # QA process and test commands
└── sessions/                          # Dated working docs from agent sessions

.claude/
├── agents/dev-team.md                 # PM / designer / dev / QA agent configs
└── skills/pr-workflow.md              # PR creation workflow
```

---

## 🧪 Running tests

```bash
xcodebuild test -project PawPal.xcodeproj -scheme PawPal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

See `docs/guides/qa-and-testing.md` for the full QA process.

---

## 📚 Docs

| Doc | What it covers |
|---|---|
| `docs/testing.md` | How to validate changes |
| `docs/database.md` | Schema design and table guide |
| `docs/pr-template.md` | PR description standard |
| `docs/decisions.md` | Architectural and product decisions and their reasoning |
| `docs/scope.md` | What is in scope, deferred, and off-limits |
| `docs/known-issues.md` | Known bugs, gaps, and tech debt |

---

## 🔧 Troubleshooting

**Build fails — Supabase config missing**
Create `PawPal/SupabaseConfig.swift` with your project URL and anon key.

**Login or feed not working**
Check that your Supabase URL and anon key are correct, migrations are applied, and RLS policies are in place.

**Images not loading after posting**
Confirm the `post-images` storage bucket exists and has public read access.
