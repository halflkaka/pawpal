# dispatch-notification

Signs an ES256 APNs JWT and sends Chinese-localized push payloads to every `device_tokens` row for a notification's recipient.

## Required secrets

Set once with the Supabase CLI against the target project:

```sh
supabase secrets set APNS_KEY_P8="$(cat AuthKey_ABC1234567.p8)"
supabase secrets set APNS_KEY_ID=ABC1234567
supabase secrets set APNS_TEAM_ID=1234567890
supabase secrets set APNS_BUNDLE_ID=com.yourorg.pawpal
supabase secrets set APNS_ENV=sandbox   # flip to production for TestFlight
```

| Secret | Purpose |
| --- | --- |
| `APNS_KEY_P8` | Full PEM contents of the `.p8` downloaded from Apple Developer. Newlines are significant. |
| `APNS_KEY_ID` | 10-char key ID shown next to the key in the Apple Developer portal. |
| `APNS_TEAM_ID` | 10-char team ID from Apple Developer → Membership. |
| `APNS_BUNDLE_ID` | Bundle identifier of the iOS target (e.g. `com.yourorg.pawpal`). Sent as the `apns-topic` header. |
| `APNS_ENV` | Default APNs environment — `sandbox` or `production`. Overridden per-token by the `env` column on `device_tokens`. |

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically by Supabase Edge Functions; you do not need to set them.

## Required Postgres settings

The trigger-side `queue_notification` helper reads these two settings to know where to POST. Run once in the SQL editor for the target project (see migration `022_push_notifications.sql`):

```sql
alter database postgres set "app.settings.dispatch_url" = 'https://<project>.functions.supabase.co/dispatch-notification';
alter database postgres set "app.settings.service_role_key" = '<service_role_secret>';
```

Without these, `likes` / `comments` / `follows` inserts still log a row in `notifications` (so nothing is lost), but no push goes out.

## Deploy

```sh
supabase functions deploy dispatch-notification --project-ref <ref>
```

## Test locally

```sh
supabase functions serve dispatch-notification --env-file .env.local
```

`.env.local` should contain the same five `APNS_*` keys plus `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`. Fire a test invocation:

```sh
curl -X POST http://localhost:54321/functions/v1/dispatch-notification \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -d '{"notification_id":"<uuid-of-an-existing-notifications-row>"}'
```

The function logs `[dispatch] id=... type=... tokens=N` for each invocation and `[dispatch] id=... token=... status=... reason=...` for every APNs failure.

## Caveat: sandbox vs production hosts

Development / debug builds produce **sandbox** APNs tokens that only `api.sandbox.push.apple.com` accepts. TestFlight + App Store builds produce **production** tokens that only `api.push.apple.com` accepts. The iOS client writes the correct `env` into `device_tokens` per-device, and this function routes per-token — so a sandbox build and a production build of the same account can coexist without manual configuration. `APNS_ENV` is only used as a fallback when a token row is missing the `env` column (shouldn't happen in normal operation, but the fallback keeps old rows from silently failing).
