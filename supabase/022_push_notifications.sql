-- 022_push_notifications.sql
-- Date: 2026-04-18
--
-- Push notifications — v1. Two tables (`device_tokens`, `notifications`)
-- plus AFTER INSERT triggers on `likes`, `comments`, `follows` that log a
-- notification row and poke the `dispatch-notification` edge function via
-- `pg_net` (`net.http_post`).
--
-- Why two tables rather than firing APNs directly from the trigger:
--
--   * `device_tokens` is the authoritative list of push destinations for
--     a given user. One row per user × device, upserted by iOS every time
--     APNs hands us a token (token rotation is real — reinstall / backup
--     restore / iCloud migration all re-issue). The edge function DELETEs
--     a row when APNs returns 410 Unregistered.
--
--   * `notifications` is the authoritative log of every push we INTEND to
--     send. Triggers insert; the edge function reads, dispatches, and
--     stamps `sent_at` (or writes a terminal error). Separating dispatch
--     from logging buys us:
--       (a) retryability — a dropped `pg_net` call is recoverable by a
--           future pg_cron sweeper over `sent_at IS NULL`.
--       (b) auditability — "did we ever try to send this?" is answered
--           with a single SELECT, not a log dive.
--       (c) future inbox — an in-app notification center (v1.5+) reads
--           this table directly via the recipient-only RLS SELECT policy.
--
-- Prerequisites (must be set ONCE by the operator in the Supabase SQL
-- editor, see PM doc 2026-04-18-pm-push-notifications.md §Prerequisites):
--
--   alter database postgres
--     set "app.settings.dispatch_url"
--     = 'https://<project>.functions.supabase.co/dispatch-notification';
--   alter database postgres
--     set "app.settings.service_role_key"
--     = '<service_role_secret>';
--
-- Without these two settings the trigger-side pg_net call becomes a
-- silent no-op — the notification row still lands (so we keep the audit
-- trail and a future sweeper can pick it up), but no push goes out until
-- the settings are populated.
--
-- This migration is idempotent and safe to re-apply: `create table if
-- not exists`, `create index if not exists`, `create or replace
-- function`, `drop policy if exists` before `create policy`, and
-- `drop trigger if exists` before `create trigger`.

-- ---------------------------------------------------------------------
-- device_tokens
-- ---------------------------------------------------------------------
--
-- Composite PK `(user_id, token)` — a given APNs token is unique per
-- device, and a user may sign in on multiple devices. The same physical
-- device signing in as two different users becomes two rows; that's
-- fine and matches how iOS surfaces notifications per-account.
--
-- `env` is kept at the row level so a sandbox-built debug install and a
-- production-built TestFlight install of the same account coexist. The
-- dispatch function picks `api.push.apple.com` vs
-- `api.sandbox.push.apple.com` per-token, not globally.

create table if not exists public.device_tokens (
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null,
  env text not null default 'sandbox' check (env in ('sandbox','production')),
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint device_tokens_pkey primary key (user_id, token)
);

create index if not exists device_tokens_user_id_idx on public.device_tokens(user_id);

-- ---------------------------------------------------------------------
-- notifications
-- ---------------------------------------------------------------------
--
-- `type` enumerates every push shape the system knows how to dispatch.
-- v1 only ships `like_post`, `comment_post`, `follow_user`; the
-- remaining seven are pre-declared so a later migration doesn't need to
-- drop-and-recreate the check constraint when milestones / playdates /
-- chat pushes come online.
--
-- `target_id` is the uuid the iOS deep-link router uses to navigate
-- after tap — post id for likes/comments, follower user id for follows,
-- pet id for birthdays, playdate id for playdate pings, conversation id
-- for chat.
--
-- `payload` is reserved for per-type extras the edge function may want
-- to stash (e.g. a comment preview, a milestone age). The function is
-- free to ignore it and re-derive from joined tables instead — the
-- column just keeps the door open.
--
-- `sent_at` / `error` are the dispatch-result columns. Exactly one of
-- them becomes non-null once the edge function resolves the row. Rows
-- with both null are either in-flight or dropped (future sweeper).

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_user_id uuid not null references public.profiles(id) on delete cascade,
  actor_user_id uuid references public.profiles(id) on delete set null,
  type text not null check (type in (
    'like_post',
    'comment_post',
    'follow_user',
    'birthday_today',
    'playdate_invited',
    'playdate_t_minus_24h',
    'playdate_t_minus_1h',
    'playdate_t_plus_2h',
    'chat_message',
    'system'
  )),
  target_id uuid,
  payload jsonb not null default '{}'::jsonb,
  sent_at timestamptz,
  error text,
  created_at timestamptz not null default now()
);

create index if not exists notifications_recipient_idx
  on public.notifications(recipient_user_id, created_at desc);
create index if not exists notifications_unsent_idx
  on public.notifications(created_at)
  where sent_at is null and error is null;

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------
--
-- device_tokens: the owning user has full CRUD on their own rows. No
--                other reader. The edge function bypasses RLS via the
--                service role key, which is how it deletes stale tokens
--                on APNs 410.
--
-- notifications: the recipient can SELECT their own rows (the future
--                inbox). Writes are service-role only — the insert path
--                is the `queue_notification` helper which is
--                SECURITY DEFINER, and the dispatch-side UPDATE runs
--                from the edge function with the service key. There is
--                NO client-facing INSERT/UPDATE/DELETE policy on this
--                table, which is the correct posture (no spoofed
--                notifications).

alter table public.device_tokens enable row level security;
alter table public.notifications enable row level security;

drop policy if exists "device_tokens_select_owner" on public.device_tokens;
create policy "device_tokens_select_owner" on public.device_tokens
  for select
  using (auth.uid() = user_id);

drop policy if exists "device_tokens_insert_owner" on public.device_tokens;
create policy "device_tokens_insert_owner" on public.device_tokens
  for insert
  with check (auth.uid() = user_id);

drop policy if exists "device_tokens_update_owner" on public.device_tokens;
create policy "device_tokens_update_owner" on public.device_tokens
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "device_tokens_delete_owner" on public.device_tokens;
create policy "device_tokens_delete_owner" on public.device_tokens
  for delete
  using (auth.uid() = user_id);

drop policy if exists "notifications_select_recipient" on public.notifications;
create policy "notifications_select_recipient" on public.notifications
  for select
  using (auth.uid() = recipient_user_id);

-- ---------------------------------------------------------------------
-- queue_notification
-- ---------------------------------------------------------------------
--
-- Central enqueue helper used by every trigger. Inserts a
-- `notifications` row AND (best-effort) kicks `pg_net.http_post` at the
-- edge function so dispatch happens in near-real-time. SECURITY DEFINER
-- so the calling trigger (which runs as the inserting user) can write a
-- row targeted at a DIFFERENT recipient without hitting RLS.
--
-- Self-notifications short-circuit — we never want to tell a user they
-- liked their own post / commented on their own post / followed
-- themselves.
--
-- If `app.settings.dispatch_url` is empty, the pg_net call is skipped
-- and the row is left for a future sweeper. This keeps the migration
-- safe to apply on projects that haven't set the secret yet (the row
-- lands with `sent_at IS NULL AND error IS NULL` — the natural "not
-- yet attempted" state).

create or replace function public.queue_notification(
  _recipient uuid,
  _actor uuid,
  _type text,
  _target uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  _id uuid;
  _dispatch_url text;
  _service_key text;
begin
  -- Self-notify short-circuit.
  if _recipient is null or _recipient = _actor then
    return null;
  end if;

  insert into public.notifications (recipient_user_id, actor_user_id, type, target_id)
  values (_recipient, _actor, _type, _target)
  returning id into _id;

  -- NOTE: both of these settings are populated by the operator once,
  -- via `alter database postgres set ...`. See the header comment for
  -- the exact commands. `current_setting(..., true)` returns NULL
  -- instead of raising when the setting is unset, which lets this
  -- function keep working on a pristine project.
  _dispatch_url := current_setting('app.settings.dispatch_url', true);
  _service_key := current_setting('app.settings.service_role_key', true);

  if _dispatch_url is not null and _dispatch_url <> '' then
    begin
      perform net.http_post(
        url := _dispatch_url,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || coalesce(_service_key, '')
        ),
        body := jsonb_build_object('notification_id', _id)
      );
    exception when others then
      -- pg_net is fire-and-forget; if the extension is missing or the
      -- call raises, swallow it so the originating INSERT (like /
      -- comment / follow) still commits. The notification row stays
      -- behind for a future sweeper or manual dispatch.
      null;
    end;
  end if;

  return _id;
end;
$$;

-- ---------------------------------------------------------------------
-- likes → notification
-- ---------------------------------------------------------------------
--
-- The inserter is the liker (`NEW.user_id`); the recipient is the
-- post's owner, which lives on `posts.owner_user_id`. Reminder:
-- `likes.user_id` references `auth.users(id)` directly (see 010), not
-- `profiles(id)`, but because `profiles.id = auth.users.id` 1:1 this
-- still flows through `queue_notification` cleanly.

create or replace function public.likes_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _owner uuid;
begin
  select owner_user_id into _owner
  from public.posts
  where id = new.post_id;

  if _owner is null then
    return new;
  end if;

  perform public.queue_notification(_owner, new.user_id, 'like_post', new.post_id);
  return new;
end;
$$;

drop trigger if exists likes_notify_after_insert on public.likes;
create trigger likes_notify_after_insert
  after insert on public.likes
  for each row execute function public.likes_notify();

-- ---------------------------------------------------------------------
-- comments → notification
-- ---------------------------------------------------------------------
--
-- Same shape as likes — look up the post owner, then enqueue. The edge
-- function pulls the comment text (first 80 chars + ellipsis) for the
-- push body, so we don't need to stash it in `payload` here.

create or replace function public.comments_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _owner uuid;
begin
  select owner_user_id into _owner
  from public.posts
  where id = new.post_id;

  if _owner is null then
    return new;
  end if;

  perform public.queue_notification(_owner, new.user_id, 'comment_post', new.post_id);
  return new;
end;
$$;

drop trigger if exists comments_notify_after_insert on public.comments;
create trigger comments_notify_after_insert
  after insert on public.comments
  for each row execute function public.comments_notify();

-- ---------------------------------------------------------------------
-- follows → notification
-- ---------------------------------------------------------------------
--
-- Recipient is the followed user; actor is the follower. Target is the
-- follower's user id so the deep-link router takes the recipient to
-- the follower's profile on tap (not their own profile — see PM doc
-- §Notification types).

create or replace function public.follows_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.queue_notification(
    new.followed_user_id,
    new.follower_user_id,
    'follow_user',
    new.follower_user_id
  );
  return new;
end;
$$;

drop trigger if exists follows_notify_after_insert on public.follows;
create trigger follows_notify_after_insert
  after insert on public.follows
  for each row execute function public.follows_notify();

-- Nudge PostgREST to refresh its schema cache so the new tables are
-- immediately visible to the iOS client without a project restart.
notify pgrst, 'reload schema';
