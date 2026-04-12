# Known Issues & Tech Debt

Things that are broken, deferred, or need attention. Keep this up to date as issues are resolved or discovered.

---

## Testing

- **`testCanAddPetAndSeeItInProfilesAndHome` always fails** — the test requires a logged-in Supabase session but there is no mock auth layer. It gets further than before (accessibility identifiers are wired up) but stalls at the pet name field. Fix requires either a `UI_TESTING` mock path in the app or a dedicated test account with pre-seeded data.

## Known Gaps

- **Discover tab resets to Posts on every re-entry** — `ContactsView` is a `@State`-owning view and is recreated each time the user switches tabs in `MainTabView`. The selected tab (Posts/Pets) and the species filter reset to defaults. Fix requires lifting `discoverTab` and `petSpeciesFilter` into a shared `@StateObject` coordinator or `MainTabView`. Low urgency for v1.

- **Pet profile post tiles are not tappable** — `PetProfileView` renders a 2-column post grid but tiles have no tap handler. Same gap exists in `ProfileView`'s post grid. Both need a post detail view to link to.
