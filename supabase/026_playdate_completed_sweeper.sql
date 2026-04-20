-- 026_playdate_completed_sweeper.sql
-- Date: 2026-04-19
--
-- Server-side sweeper that flips `playdates.status` from 'accepted' →
-- 'completed' at T+2h after `scheduled_at`. Runs every 15 minutes via
-- pg_cron.
--
-- Why we need this:
--
--   Today the 'accepted' → 'completed' transition is driven by a local
--   iOS notification scheduled on-device for T+2h after `scheduled_at`
--   (one of the three `playdate_t_*` device-scheduled reminders noted
--   in migration 023). The flip only happens when the user actually
--   opens the app inside that notification window. In practice that's
--   flaky:
--
--     * The notification can fire while the app is backgrounded and
--       never be acted on.
--     * The user may have denied notifications entirely, in which case
--       nothing on-device ever nudges the state forward.
--     * The user may uninstall / reinstall, wiping the scheduled
--       UNNotificationRequest.
--     * Both participants might simply stop looking at that playdate
--       after the walk, leaving the row stuck in 'accepted' forever.
--
--   A server-side sweeper guarantees eventual consistency: by T+2h15m
--   at the latest, any accepted playdate whose scheduled_at has passed
--   the +2h mark is marked completed server-side, independent of what
--   either device does.
--
-- Why 15-minute cadence:
--
--   It's a trade-off between freshness and scheduler load. 1 minute
--   would be wasteful (the playdate detail view already renders relative
--   time — "刚刚结束" / "2小时前" — so a ±15min lag on the status flip
--   is imperceptible to the user). 1 hour would leave rows stale long
--   enough that a user refreshing the feed right after T+2h would still
--   see the old status and wonder why. 15 minutes splits the difference
--   cleanly and matches the cadence other Supabase projects use for
--   light cron sweepers.
--
-- What happens if pg_cron isn't enabled on the project:
--
--   `create extension if not exists pg_cron with schema extensions;`
--   will FAIL on Supabase plans / projects where pg_cron is not
--   available or not yet enabled. This is not silent — the migration
--   will error out at the first statement.
--
--   To fix: the operator must enable pg_cron manually in the Supabase
--   dashboard (Database → Extensions → pg_cron → toggle on). Once
--   enabled, re-running this migration is safe — the
--   `create extension if not exists` is a no-op on an already-enabled
--   extension, and the `do $$ ... end $$` block below short-circuits
--   if the cron job is already scheduled.
--
-- Why SECURITY DEFINER:
--
--   pg_cron runs jobs as the postgres superuser role by default, so
--   strictly speaking `sweep_completed_playdates()` doesn't NEED
--   SECURITY DEFINER to bypass RLS in the cron-triggered path. We
--   declare it anyway to document intent (the function is designed to
--   update rows across ALL users, not rows owned by the caller) and so
--   the function works from other callers — an ops script invoked via
--   the Supabase SQL editor, a one-off manual sweep, or a future edge
--   function that wants to force-complete a playdate — without each of
--   those callers needing superuser privileges.
--
-- Idempotency:
--
--   * `create extension if not exists` — no-op on re-run.
--   * `create or replace function` — redefines the function in place.
--   * The `do $$ ... end $$` block below guards `cron.schedule(...)`
--     with a `cron.job.jobname` check, so a second migration run finds
--     the existing job and does nothing. We do NOT use
--     `cron.unschedule` + `cron.schedule` because the job id would
--     churn on every apply and any admin-side observability hooked to
--     the id would lose its handle.
--
-- Prerequisites: migration 023 (for `public.playdates`) must have been
-- applied. pg_cron must be enabled on the project (see note above).

-- ---------------------------------------------------------------------
-- pg_cron
-- ---------------------------------------------------------------------
-- Supabase convention: pg_cron lives in the `extensions` schema, not
-- `public`. The `extensions` schema is created by the Supabase base
-- image; on a vanilla Postgres it would need to be created first. We
-- assume the Supabase layout here because every other PawPal migration
-- does.
create extension if not exists pg_cron with schema extensions;

-- ---------------------------------------------------------------------
-- sweep_completed_playdates
-- ---------------------------------------------------------------------
--
-- The single UPDATE is the whole job. Indexed on
-- `(invitee_user_id, status)` and `(proposer_user_id, status)` — neither
-- is a perfect match for this WHERE clause, but the planner can use
-- either as a filter and then check `scheduled_at`. Volumes are tiny
-- (MVP scale) so a seq scan would also be fine; the indexes exist for
-- the feed-side queries, not this sweeper.
--
-- We explicitly set `updated_at = now()` so the row's mtime reflects
-- the server-side transition. Clients that sort or filter by
-- `updated_at` will correctly see the flip as a fresh event.

create or replace function public.sweep_completed_playdates()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.playdates
     set status = 'completed',
         updated_at = now()
   where status = 'accepted'
     and scheduled_at < now() - interval '2 hours';
end;
$$;

-- ---------------------------------------------------------------------
-- cron schedule — every 15 minutes
-- ---------------------------------------------------------------------
--
-- Gated on `cron.job.jobname` so the second migration run is a no-op.
-- If the job is missing (first run, or an operator manually unscheduled
-- it) we schedule it; if it's already there we leave it alone.
--
-- The job name `sweep_completed_playdates` doubles as the lookup key —
-- keep it in sync with the function name for grep-ability.

do $$
begin
  if not exists (
    select 1 from cron.job where jobname = 'sweep_completed_playdates'
  ) then
    perform cron.schedule(
      'sweep_completed_playdates',
      '*/15 * * * *',
      $cron$ select public.sweep_completed_playdates(); $cron$
    );
  end if;
end $$;

-- Nudge PostgREST to refresh its schema cache. No client-visible schema
-- change here, but we keep the notify for consistency with every other
-- PawPal migration — cheaper to always notify than to debug a stale
-- cache later.
notify pgrst, 'reload schema';
