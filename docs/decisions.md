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

_Add new entries here when significant architectural, product, or design decisions are made. Changelog captures what changed; this captures why._
