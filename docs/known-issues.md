# Known Issues & Tech Debt

Things that are broken, deferred, or need attention. Keep this up to date as issues are resolved or discovered.

---

## Testing

- **`testCanAddPetAndSeeItInProfilesAndHome` always fails** — the test requires a logged-in Supabase session but there is no mock auth layer. It gets further than before (accessibility identifiers are wired up) but stalls at the pet name field. Fix requires either a `UI_TESTING` mock path in the app or a dedicated test account with pre-seeded data.

## Known Gaps

- **Storage bucket must be created manually** — `supabase/004_storage.sql` only contains comments; the `post-images` bucket is never created by migration. It must be created in the Supabase dashboard (Storage → New bucket → name: `post-images`, public read). `AvatarService` uses the same bucket for pet avatars, so if avatars display, the bucket already exists. If post images fail with a "Bucket not found" error it will now surface visibly in the create-post button bar.

---

## Recently Resolved

- **Post images never saved or displayed** — `RemotePostImage`, the PostgREST select strings, and the `post_images` INSERT struct all used column names `image_url`/`sort_order` instead of the actual live DB column names `url`/`position` (established by migration `011_align_post_images_columns.sql`). This caused every `post_images` SELECT to fall back to the bare `*, pets(*)` level (no images) and every INSERT to be rejected. Fixed column names throughout; also hardened the `position` field to `Int` (was `String`), added rollback-on-failure for image uploads, and surfaced upload errors in the always-visible button bar (2026-04-12).
