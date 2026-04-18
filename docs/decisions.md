# Decision Log

Architectural, product, and design-philosophy decisions worth preserving. These explain *why* the app is built the way it is — so future developers and AI agents don't accidentally undo deliberate choices.

Each entry: what was decided, why, and what it means going forward.

---

## Supabase is the single source of truth

**Decision:** All data is fetched from and written to Supabase. SwiftData local caching was removed.

**Why:** Local caching added complexity (sync conflicts, stale state, cache invalidation) without meaningful benefit for an app that assumes an active internet connection. Supabase handles persistence, auth, and storage — a single layer is simpler to reason about and debug.

**Implications:** Do not reintroduce SwiftData or local caching. `SwiftDataModels.swift` exists but is intentionally empty. Offline support is not a current goal.

---

## Social graph is user-to-user, not pet-to-pet

**Decision:** Follow relationships are between user accounts (`follower_user_id → followed_user_id`), not between pet profiles.

**Why:** Keeps feed queries simple. A user-to-user graph means one join to get a feed; pet-to-pet would require resolving pet ownership before filtering posts. Most users own one pet anyway.

**Implications:** Do not add pet-level follow without revisiting feed query design. Phase 4 explores pet-specific follow — that is a deliberate future decision, not an oversight.

---

## Profiles are lightweight; pets are the social actors

**Decision:** `profiles` holds only account-level identity (username, display name, avatar). `pets` holds the rich social identity (species, breed, bio, home city, personality).

**Why:** The app is pet-first. The human account exists for login, ownership, and trust. Pets are the visible, expressive presence in the feed. Keeping profiles lean makes it easier to evolve pet profiles independently.

**Implications:** When adding social features, default to putting attributes on pets, not profiles. Email stays in Supabase auth and is never duplicated in `profiles`.

---

## Chinese-first UI

**Decision:** All user-facing text in the app is written in Chinese (Simplified).

**Why:** The primary target audience is Chinese-speaking users.

**Implications:** All new UI strings should be in Chinese. Do not add English-language UI text without explicit instruction.

---

## Shared Supabase client across services

**Decision:** All services use `SupabaseConfig.client` — a single shared `SupabaseClient` instance — rather than each service instantiating its own.

**Why:** A shared client ensures all services operate on the same authenticated session and RLS context. Multiple clients caused inconsistent auth state across services.

**Implications:** Always use `SupabaseConfig.client` in new services. Do not instantiate `SupabaseClient` directly inside a service.

---

## Posts are preserved when a pet is deleted

**Decision:** `posts.pet_id` uses `ON DELETE SET NULL` rather than `ON DELETE CASCADE`.

**Why:** A user's post history should survive even if they remove a pet profile. Deleting a pet is not the same as deleting the memories associated with it.

**Implications:** The app must handle `post.pet_id == nil` gracefully in all views. Do not assume a post always has an associated pet.

---

## Feed is chronological, not algorithmic

**Decision:** The home feed is ordered by `created_at DESC`. No ranking, weighting, or personalisation logic.

**Why:** Algorithmic feeds require engagement signals, infrastructure, and tuning. The app is too early for this. Chronological is simple, predictable, and fair to all users.

**Implications:** Do not add ranking or scoring to feed queries. This is explicitly deferred to Phase 6 in `ROADMAP.md`.

---

## MapKit for city autocomplete in pet editor

**Decision:** The pet editor's home city field uses `MKLocalSearchCompleter` (MapKit) rather than a plain `TextField`.

**Why:** Free-text city entry produced inconsistent values (different spellings, missing regions) that are hard to display or query against. `MKLocalSearchCompleter` returns structured, real-world place names that are consistent and user-friendly to select.

**Implications:** `MapKit` is now a dependency of `ProfileView.swift`. The `LocationCompleter` class and `LocationPickerSheet` view live at the bottom of that file. Do not duplicate location search logic elsewhere — extract to a shared file if needed in more places.

---

## 2026 "warm serif + polaroid" visual refresh

**Decision:** The app's visual language was refactored against a new design prototype (`_standalone_.html` / `design_extract/`). The refactor touches every primary screen — Feed, Profile, Virtual Pet, Tab bar, Chat — plus the shared `PawPalDesignSystem.swift` palette. Chat was pulled forward from Phase 5 at the user's explicit request even though `docs/scope.md` had deferred it.

**Why:** The previous palette was a bright, saturated orange on pure white that read as generic; the new direction is a warm cream (`#FAF6F0`) background, a single warm-orange accent (`#FF7A52`), serif ("Fraunces" → `.serif` fallback) for wordmarks and pet names, and polaroid-style post cards with alternating tilt. The result is more magazine/journal than social-network. Pet-first identity is reinforced with vector `DogAvatar` fallbacks for every breed, and a playful `VirtualPetView` stage on dog profiles.

**Implications:**
- `PawPalDesignSystem.swift` is the authoritative palette. New screens must use its tokens (`PawPalTheme.accent`, `PawPalTheme.cardSoft`, `PawPalTheme.hairline`, `PawPalTheme.online`, etc.) rather than hardcoding colours.
- Old token names (`PawPalTheme.orange`, `.orangeSoft`, `.orangeGlow`) are kept as backward-compat aliases so ancillary files keep compiling. Do not resurrect these names in new code — prefer `accent` / `accentSoft` / `accentGlow`.
- `DogAvatar` is the breed-aware vector fallback used everywhere a pet photo might be missing. The chain is: real photo → `DogAvatar` (for dogs) → species SF Symbol → emoji. `PetCharacterView` is still rendered for non-dog species so we don't regress cats/rabbits/birds.
- `VirtualPetView` replaces `PetCharacterView` for dogs on the profile. It's decorative only — hunger/energy are derived from `PetStats` heuristically (no backend persistence).
- `ChatListView` + new `ChatDetailView` are local-only (no backend). Do not treat the sample data as production-ready; real chat requires a Supabase messaging table + realtime subscription, which is still in Phase 5.
- The Chinese-first UI rule is unchanged — all strings introduced by the refactor are in Simplified Chinese.

---

_Add new entries here when significant architectural, product, or design decisions are made. Changelog captures what changed; this captures why._
