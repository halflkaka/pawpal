// dispatch-notification
//
// Edge function that reads a `notifications` row, builds a localized
// (zh-Hans) APS payload, signs an ES256 APNs JWT, and POSTs to every
// device token registered for the recipient. Invoked from the trigger
// pipeline (`pg_net.http_post` inside `queue_notification`) with a
// body of `{ "notification_id": "<uuid>" }`.
//
// See /supabase/functions/dispatch-notification/README.md for the
// required secrets, deploy command, and local-test snippet.
//
// Flow:
//   1. Parse { notification_id }.
//   2. Load the notification row + actor profile + (if applicable)
//      post owner's pet name + comment preview.
//   3. Load every `device_tokens` row for the recipient.
//   4. Build the APS payload per `type`.
//   5. Sign (or re-use cached) ES256 JWT with APNS_KEY_P8.
//   6. POST to api.push.apple.com (prod) or api.sandbox.push.apple.com
//      (sandbox), per-token.
//   7. On 200: accumulate. On 410: DELETE the token row. On 429/5xx:
//      single retry after 1s, then record error.
//   8. UPDATE notifications SET sent_at = now(), error = <aggregated>.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ---------------------------------------------------------------------
// Config / env
// ---------------------------------------------------------------------

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const APNS_KEY_P8 = Deno.env.get('APNS_KEY_P8') ?? '';
const APNS_KEY_ID = Deno.env.get('APNS_KEY_ID') ?? '';
const APNS_TEAM_ID = Deno.env.get('APNS_TEAM_ID') ?? '';
const APNS_BUNDLE_ID = Deno.env.get('APNS_BUNDLE_ID') ?? '';
const APNS_ENV_DEFAULT = (Deno.env.get('APNS_ENV') ?? 'sandbox').toLowerCase();

const APNS_HOST_PROD = 'api.push.apple.com';
const APNS_HOST_SANDBOX = 'api.sandbox.push.apple.com';

// ---------------------------------------------------------------------
// JWT cache
// ---------------------------------------------------------------------
//
// APNs accepts a JWT for up to 60 minutes; we cache for 50. The cache
// is module-scope so warm edge-function invocations re-use the signed
// token instead of re-importing the p8 and re-signing on every push.

let cachedJwt: { token: string; expiresAt: number } | null = null;
let cachedSigningKey: CryptoKey | null = null;

const JWT_TTL_SECONDS = 50 * 60;

// ---------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------

interface NotificationRow {
  id: string;
  recipient_user_id: string;
  actor_user_id: string | null;
  type: string;
  target_id: string | null;
  payload: Record<string, unknown>;
  sent_at: string | null;
  error: string | null;
  created_at: string;
}

interface ActorProfile {
  id: string;
  display_name: string | null;
  username: string | null;
}

interface DeviceToken {
  token: string;
  env: string | null;
}

interface ApsPayload {
  aps: {
    alert: { title: string; body: string };
    sound: string;
    badge: number;
  };
  type: string;
  target_id: string | null;
}

interface DispatchError {
  token: string;
  status: number;
  reason?: string;
}

// ---------------------------------------------------------------------
// Supabase client — service role, bypasses RLS.
// ---------------------------------------------------------------------

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

// ---------------------------------------------------------------------
// Entrypoint
// ---------------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 });
  }

  let body: { notification_id?: string };
  try {
    body = await req.json();
  } catch {
    return new Response('Invalid JSON', { status: 400 });
  }

  const notificationId = body.notification_id;
  if (!notificationId) {
    return new Response('Missing notification_id', { status: 400 });
  }

  try {
    const result = await dispatch(notificationId);
    return new Response(JSON.stringify(result), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error('[dispatch] fatal', err);
    return new Response(`Dispatch failed: ${String(err)}`, { status: 500 });
  }
});

// ---------------------------------------------------------------------
// Dispatch one notification row.
// ---------------------------------------------------------------------

async function dispatch(notificationId: string) {
  const { data: notification, error: notifErr } = await supabase
    .from('notifications')
    .select('*')
    .eq('id', notificationId)
    .maybeSingle();

  if (notifErr || !notification) {
    throw new Error(`notification not found: ${notifErr?.message ?? 'null row'}`);
  }

  const n = notification as NotificationRow;

  // Skip if already dispatched (e.g. pg_net retried during a transient
  // Supabase hiccup). Idempotent by design.
  if (n.sent_at) {
    console.log(`[dispatch] id=${n.id} already sent, skipping`);
    return { status: 'already_sent' };
  }

  // Load actor profile for title/body interpolation.
  let actor: ActorProfile | null = null;
  if (n.actor_user_id) {
    const { data: actorData } = await supabase
      .from('profiles')
      .select('id, display_name, username')
      .eq('id', n.actor_user_id)
      .maybeSingle();
    actor = (actorData as ActorProfile) ?? null;
  }

  // For like/comment we also want the recipient's pet name for the
  // body copy ("... gave your {pet_name} a like"). Pet name lives on
  // `pets` joined via `posts.pet_id`. Fallback to the empty string if
  // the post is pet-less.
  let petName = '';
  let commentPreview = '';

  if ((n.type === 'like_post' || n.type === 'comment_post') && n.target_id) {
    const { data: postRow } = await supabase
      .from('posts')
      .select('id, pet_id, pets:pets!posts_pet_id_fkey(name)')
      .eq('id', n.target_id)
      .maybeSingle();
    // deno-lint-ignore no-explicit-any
    const pet = (postRow as any)?.pets;
    if (pet && typeof pet === 'object') {
      if (Array.isArray(pet)) {
        petName = pet[0]?.name ?? '';
      } else {
        petName = pet.name ?? '';
      }
    }
  }

  if (n.type === 'comment_post' && n.actor_user_id && n.target_id) {
    // Pull the most recent comment the actor made on this post — that's
    // the one that triggered the notification. This is simpler than
    // threading the comment id through `payload`.
    const { data: commentRow } = await supabase
      .from('comments')
      .select('content, created_at')
      .eq('post_id', n.target_id)
      .eq('user_id', n.actor_user_id)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    // deno-lint-ignore no-explicit-any
    const content: string = (commentRow as any)?.content ?? '';
    commentPreview = content.length > 80 ? `${content.slice(0, 80)}…` : content;
  }

  // For playdate_invited we want both pets' names and the scheduled
  // timestamp so the body can read "{proposer_pet} 想和 {invitee_pet}
  // {relative when}遛弯". The three `playdate_t_*` reminder types are
  // device-scheduled (see LocalNotificationsService) and never hit this
  // edge function — if they ever did, they'd fall through to the
  // default branch and be marked unsupported_type. That's by design.
  let proposerPetName = '';
  let inviteePetName = '';
  let scheduledAtISO = '';

  if (n.type === 'playdate_invited' && n.target_id) {
    const { data: pd } = await supabase
      .from('playdates')
      .select('scheduled_at, proposer_pet:pets!proposer_pet_id(name), invitee_pet:pets!invitee_pet_id(name)')
      .eq('id', n.target_id)
      .maybeSingle();
    // deno-lint-ignore no-explicit-any
    const row = pd as any;
    proposerPetName = row?.proposer_pet?.name ?? row?.proposer_pet?.[0]?.name ?? '毛孩子';
    inviteePetName  = row?.invitee_pet?.name  ?? row?.invitee_pet?.[0]?.name  ?? '毛孩子';
    scheduledAtISO  = row?.scheduled_at ?? '';
  }

  // Load device tokens.
  const { data: tokenRows, error: tokenErr } = await supabase
    .from('device_tokens')
    .select('token, env')
    .eq('user_id', n.recipient_user_id);

  if (tokenErr) {
    throw new Error(`device_tokens query failed: ${tokenErr.message}`);
  }

  const tokens = (tokenRows ?? []) as DeviceToken[];

  console.log(`[dispatch] id=${n.id} type=${n.type} tokens=${tokens.length}`);

  if (tokens.length === 0) {
    await supabase
      .from('notifications')
      .update({ error: 'no_device', sent_at: new Date().toISOString() })
      .eq('id', n.id);
    return { status: 'no_device' };
  }

  const payload = buildPayload(
    n,
    actor,
    petName,
    commentPreview,
    proposerPetName,
    inviteePetName,
    scheduledAtISO,
  );
  if (!payload) {
    await supabase
      .from('notifications')
      .update({ error: `unsupported_type:${n.type}`, sent_at: new Date().toISOString() })
      .eq('id', n.id);
    return { status: 'unsupported_type' };
  }

  // Sign once per invocation (cached module-wide).
  const jwt = await getApnsJwt();

  const errors: DispatchError[] = [];
  let successes = 0;

  for (const t of tokens) {
    const env = (t.env ?? APNS_ENV_DEFAULT).toLowerCase();
    const host = env === 'production' ? APNS_HOST_PROD : APNS_HOST_SANDBOX;
    const result = await sendOneWithRetry(host, t.token, jwt, payload);

    if (result.ok) {
      successes++;
      continue;
    }

    if (result.status === 410) {
      // Unregistered — drop the token row so we stop trying.
      await supabase
        .from('device_tokens')
        .delete()
        .eq('user_id', n.recipient_user_id)
        .eq('token', t.token);
      errors.push({ token: t.token, status: 410, reason: 'unregistered' });
      continue;
    }

    errors.push({ token: t.token, status: result.status, reason: result.reason });
    console.error(`[dispatch] id=${n.id} token=${truncate(t.token)} status=${result.status} reason=${result.reason ?? ''}`);
  }

  const aggregatedError = errors.length > 0 ? JSON.stringify(errors).slice(0, 2000) : null;

  await supabase
    .from('notifications')
    .update({ sent_at: new Date().toISOString(), error: aggregatedError })
    .eq('id', n.id);

  return { status: 'done', successes, failures: errors.length };
}

// ---------------------------------------------------------------------
// Payload builders — Chinese copy verbatim from PM doc.
// ---------------------------------------------------------------------

function buildPayload(
  n: NotificationRow,
  actor: ActorProfile | null,
  petName: string,
  commentPreview: string,
  proposerPetName: string,
  inviteePetName: string,
  scheduledAtISO: string,
): ApsPayload | null {
  const actorName = actor?.display_name || actor?.username || '有人';

  switch (n.type) {
    case 'like_post': {
      const pet = petName || '毛孩子';
      return {
        aps: {
          alert: {
            title: '小爱心 ❤️',
            body: `${actorName} 给你的 ${pet} 点赞了`,
          },
          sound: 'default',
          badge: 1,
        },
        type: 'like_post',
        target_id: n.target_id,
      };
    }

    case 'comment_post': {
      const preview = commentPreview || '给你留言了';
      return {
        aps: {
          alert: {
            title: '新评论 💬',
            body: `${actorName}: ${preview}`,
          },
          sound: 'default',
          badge: 1,
        },
        type: 'comment_post',
        target_id: n.target_id,
      };
    }

    case 'follow_user': {
      return {
        aps: {
          alert: {
            title: '新的关注者 🐾',
            body: `${actorName} 关注了你`,
          },
          sound: 'default',
          badge: 1,
        },
        type: 'follow_user',
        target_id: n.target_id,
      };
    }

    case 'playdate_invited': {
      // `formatRelativeZh` degrades to an empty string when scheduledAt
      // is empty or invalid — the body reads "{proposer} 想和 {invitee}
      // 遛弯" in that edge case, which is still intelligible.
      const when = formatRelativeZh(scheduledAtISO);
      const proposer = proposerPetName || '毛孩子';
      const invitee = inviteePetName || '毛孩子';
      return {
        aps: {
          alert: {
            title: '新的遛弯邀请 🐾',
            body: `${proposer} 想和 ${invitee} ${when}遛弯`,
          },
          sound: 'default',
          badge: 1,
        },
        type: 'playdate_invited',
        target_id: n.target_id,
      };
    }

    default:
      // `playdate_t_minus_24h` / `playdate_t_minus_1h` /
      // `playdate_t_plus_2h` are declared in the migration 022 CHECK
      // constraint but intentionally unhandled here — they're owned by
      // LocalNotificationsService on the device. `birthday_today` /
      // `chat_message` are also pre-declared for later phases.
      return null;
  }
}

// ---------------------------------------------------------------------
// APNs HTTP/2 send with one retry.
// ---------------------------------------------------------------------

async function sendOneWithRetry(
  host: string,
  token: string,
  jwt: string,
  payload: ApsPayload,
): Promise<{ ok: true } | { ok: false; status: number; reason?: string }> {
  const first = await sendOne(host, token, jwt, payload);
  if (first.ok) return first;

  // 410 is terminal — never retry.
  if (first.status === 410) return first;

  // 429 / 5xx: single retry after 1s. Everything else: bail.
  if (first.status === 429 || (first.status >= 500 && first.status < 600)) {
    await new Promise((r) => setTimeout(r, 1000));
    return await sendOne(host, token, jwt, payload);
  }

  return first;
}

async function sendOne(
  host: string,
  token: string,
  jwt: string,
  payload: ApsPayload,
): Promise<{ ok: true } | { ok: false; status: number; reason?: string }> {
  const url = `https://${host}/3/device/${token}`;
  try {
    // Deno's native fetch speaks HTTP/2 transparently when the remote
    // supports it — APNs requires HTTP/2 and will refuse HTTP/1.1.
    const resp = await fetch(url, {
      method: 'POST',
      headers: {
        authorization: `bearer ${jwt}`,
        'apns-topic': APNS_BUNDLE_ID,
        'apns-push-type': 'alert',
        'content-type': 'application/json',
      },
      body: JSON.stringify(payload),
    });

    if (resp.status === 200) {
      return { ok: true };
    }

    let reason: string | undefined;
    try {
      const json = await resp.json();
      reason = typeof json?.reason === 'string' ? json.reason : undefined;
    } catch {
      // APNs returns an empty body on 200; non-JSON bodies just skip
      // the reason field.
    }

    return { ok: false, status: resp.status, reason };
  } catch (err) {
    return { ok: false, status: 0, reason: String(err) };
  }
}

// ---------------------------------------------------------------------
// ES256 JWT signing with Web Crypto.
// ---------------------------------------------------------------------
//
// APNs requires a JWT signed ES256 (ECDSA P-256 + SHA-256) with the .p8
// key Apple issued. The key file is PEM PKCS#8 — i.e. it looks like:
//
//   -----BEGIN PRIVATE KEY-----
//   MIGTAgEA...
//   -----END PRIVATE KEY-----
//
// To feed it to `crypto.subtle.importKey`, we:
//
//   1. Strip the PEM header/footer and whitespace.
//   2. Base64-decode to raw DER bytes.
//   3. Import as `pkcs8` with `{ name: 'ECDSA', namedCurve: 'P-256' }`.
//
// `crypto.subtle.sign` for ECDSA emits the signature in IEEE P1363
// (raw r || s) format — which is exactly what JOSE / JWT expects. No
// ASN.1/DER rewrapping needed (unlike OpenSSL's default output).
//
// This is the trickiest part of the file. If signing ever breaks, the
// likely culprits are: (1) the .p8 contents being stored with escaped
// \n instead of real newlines in the secret, or (2) the key curve
// being wrong. Check both before anything else.

async function getApnsJwt(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  if (cachedJwt && cachedJwt.expiresAt > now + 60) {
    return cachedJwt.token;
  }

  if (!APNS_KEY_P8 || !APNS_KEY_ID || !APNS_TEAM_ID) {
    throw new Error('APNs signing env is incomplete (APNS_KEY_P8 / APNS_KEY_ID / APNS_TEAM_ID)');
  }

  if (!cachedSigningKey) {
    cachedSigningKey = await importP8(APNS_KEY_P8);
  }

  const header = { alg: 'ES256', kid: APNS_KEY_ID, typ: 'JWT' };
  const claims = { iss: APNS_TEAM_ID, iat: now };

  const signingInput = `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(JSON.stringify(claims))}`;

  const sig = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    cachedSigningKey,
    new TextEncoder().encode(signingInput),
  );

  const jwt = `${signingInput}.${base64UrlEncodeBytes(new Uint8Array(sig))}`;

  cachedJwt = { token: jwt, expiresAt: now + JWT_TTL_SECONDS };
  return jwt;
}

async function importP8(pem: string): Promise<CryptoKey> {
  // Tolerate secrets stored with literal `\n` sequences in addition to
  // real newlines — `supabase secrets set` preserves newlines but some
  // deployment tooling double-escapes them.
  const normalized = pem.replace(/\\n/g, '\n');
  const b64 = normalized
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s+/g, '');

  const der = base64ToBytes(b64);

  return await crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );
}

// ---------------------------------------------------------------------
// Base64 / base64url helpers.
// ---------------------------------------------------------------------

function base64UrlEncode(input: string): string {
  return base64UrlEncodeBytes(new TextEncoder().encode(input));
}

function base64UrlEncodeBytes(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64ToBytes(b64: string): Uint8Array {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function truncate(s: string, n = 12): string {
  return s.length <= n ? s : `${s.slice(0, n)}…`;
}

// ---------------------------------------------------------------------
// formatRelativeZh
// ---------------------------------------------------------------------
//
// Renders a scheduled timestamp into a human Chinese phrase the push
// body reads inline: "今天早上", "明天下午", "后天晚上", "周六下午",
// or "4月20日 早上". The segment suffix is derived from the hour
// (<12 → 早上, 12–17 → 下午, ≥18 → 晚上).
//
// All date math happens in Asia/Shanghai so the app's Chinese-first UI
// matches the user's mental model regardless of where the edge function
// physically runs. We use `Intl.DateTimeFormat` with `timeZone:
// 'Asia/Shanghai'` + en-CA to get a stable YYYY-MM-DD shape, then
// compare day deltas against "today in Shanghai". This avoids pulling
// in a date library.
//
// Returns an empty string when `iso` is empty or unparseable — the
// caller's body copy reads acceptably without the phrase.

function formatRelativeZh(iso: string): string {
  if (!iso) return '';
  const scheduled = new Date(iso);
  if (isNaN(scheduled.getTime())) return '';

  const tz = 'Asia/Shanghai';

  // Shanghai-local Y/M/D for both "now" and the scheduled instant.
  const ymdFmt = new Intl.DateTimeFormat('en-CA', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
  const hourFmt = new Intl.DateTimeFormat('en-GB', {
    timeZone: tz,
    hour: '2-digit',
    hour12: false,
  });
  const weekdayFmt = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    weekday: 'short',
  });

  const now = new Date();
  const nowYmd = ymdFmt.format(now);      // e.g. "2026-04-18"
  const schYmd = ymdFmt.format(scheduled); // e.g. "2026-04-20"

  const parseYmd = (s: string): Date => {
    const [y, m, d] = s.split('-').map(Number);
    return new Date(Date.UTC(y, m - 1, d));
  };

  const nowDay = parseYmd(nowYmd);
  const schDay = parseYmd(schYmd);
  const deltaDays = Math.round((schDay.getTime() - nowDay.getTime()) / (1000 * 60 * 60 * 24));

  // Segment from the scheduled instant's Shanghai-local hour.
  const hourStr = hourFmt.format(scheduled); // "00".."23"
  const hour = parseInt(hourStr, 10);
  const segment = hour < 12 ? '早上' : hour < 18 ? '下午' : '晚上';

  let dayPhrase: string;
  if (deltaDays === 0) {
    dayPhrase = '今天';
  } else if (deltaDays === 1) {
    dayPhrase = '明天';
  } else if (deltaDays === 2) {
    dayPhrase = '后天';
  } else if (deltaDays >= 3 && deltaDays <= 6) {
    // Weekday short name → 周X.
    const weekdayMap: Record<string, string> = {
      Mon: '周一',
      Tue: '周二',
      Wed: '周三',
      Thu: '周四',
      Fri: '周五',
      Sat: '周六',
      Sun: '周日',
    };
    const wk = weekdayFmt.format(scheduled);
    dayPhrase = weekdayMap[wk] ?? wk;
  } else {
    // Fall through to M月D日 for anything further out (or in the past).
    const [, mm, dd] = schYmd.split('-').map(Number);
    dayPhrase = `${mm}月${dd}日`;
  }

  return `${dayPhrase}${segment}`;
}
