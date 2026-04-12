# Known Issues & Tech Debt

Things that are broken, deferred, or need attention. Keep this up to date as issues are resolved or discovered.

---

## Testing

- **`testCanAddPetAndSeeItInProfilesAndHome` always fails** — the test requires a logged-in Supabase session but there is no mock auth layer. It gets further than before (accessibility identifiers are wired up) but stalls at the pet name field. Fix requires either a `UI_TESTING` mock path in the app or a dedicated test account with pre-seeded data.

## Docs

- **ROADMAP.md is outdated** — it lists posts, feed, likes, comments, and follows as unimplemented stubs, but all of these are now live. Needs a full refresh to reflect current state before it can be used as a planning reference.

## Known Gaps

_Nothing else tracked yet. Add entries here as issues are discovered during development._
