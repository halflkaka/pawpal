-- 029_fix_pdp_rls_recursion.sql
-- Date: 2026-04-19
--
-- Fix: `infinite recursion detected in policy for relation
-- "playdate_participants"` on any SELECT against the junction.
--
-- What was broken:
--
--   Migration 028 declared the SELECT policy on
--   `playdate_participants` with a predicate that queries the same
--   table:
--
--     create policy "pdp_select_own_playdates"
--       on public.playdate_participants
--       for select using (
--         exists (
--           select 1 from public.playdate_participants pdp2
--           where pdp2.playdate_id = playdate_participants.playdate_id
--             and pdp2.user_id = auth.uid()
--         )
--       );
--
--   The header comment on 028 claimed this was safe because
--   `auth.uid()` is a constant within a query. That reasoning is
--   wrong. Postgres RLS applies the policy to EVERY query against
--   the table, including the subquery inside the policy itself.
--   The subquery's `select ... from playdate_participants` re-enters
--   the policy, which spawns another subquery, which re-enters the
--   policy — Postgres detects the cycle at plan time and raises
--   `42P17: infinite recursion detected in policy for relation
--   "playdate_participants"`.
--
--   The same trap also lurked in the supplementary policy on
--   `playdates` (`playdates_select_participants_via_junction`),
--   which queries `playdate_participants`. That subquery is still
--   subject to the junction's SELECT policy, so fixing the primary
--   policy resolves the secondary one for free.
--
-- The fix:
--
--   Replace the self-referential predicate with a `SECURITY DEFINER`
--   helper function `public.user_is_playdate_participant(pd_id, uid)`.
--   `SECURITY DEFINER` runs the function as its owner (postgres),
--   which BYPASSES RLS on tables the function reads — so the
--   internal `select 1 from playdate_participants` no longer
--   triggers the policy. The function is marked `stable` + a fixed
--   `search_path` to prevent search_path injection (standard Supabase
--   hardening pattern).
--
--   The policy predicate becomes a simple function call:
--
--     using (public.user_is_playdate_participant(
--              playdate_id,
--              auth.uid()
--            ))
--
--   Same semantics as the original, zero recursion, one covered-index
--   read per row-to-check.
--
-- Why a helper instead of rewriting to `user_id = auth.uid()`:
--
--   The looser predicate `user_id = auth.uid()` would restrict each
--   user to seeing ONLY their own junction rows. But for a 3-pet
--   group playdate, user A needs to see user B's and user C's
--   acceptance status to render the detail view correctly ("B has
--   accepted, C is still pending"). The helper preserves the
--   original intent — any user who has ANY row on the playdate can
--   see ALL rows on that playdate — without the recursion.
--
-- Idempotency:
--
--   * `create or replace function` on the helper — safe to re-run.
--   * `drop policy if exists` + `create policy` on both policies —
--     safe to re-run.
--   * `revoke` / `grant execute` is last-write-wins.
--
-- Prerequisites: migration 028 applied (table + policies exist).
-- Safe to re-apply.

-- ---------------------------------------------------------------------
-- SECURITY DEFINER helper — bypasses RLS on the lookup
-- ---------------------------------------------------------------------

create or replace function public.user_is_playdate_participant(
  pd_id uuid,
  uid uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.playdate_participants
    where playdate_id = pd_id
      and user_id = uid
  );
$$;

revoke all on function public.user_is_playdate_participant(uuid, uuid) from public;
grant execute on function public.user_is_playdate_participant(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Rewrite the SELECT policy on playdate_participants
-- ---------------------------------------------------------------------

drop policy if exists "pdp_select_own_playdates" on public.playdate_participants;

create policy "pdp_select_own_playdates" on public.playdate_participants
  for select
  using (
    public.user_is_playdate_participant(playdate_id, auth.uid())
  );

-- ---------------------------------------------------------------------
-- Rewrite the supplementary SELECT policy on playdates to use the
-- same helper
-- ---------------------------------------------------------------------
--
-- The original policy queried `playdate_participants` directly. Now
-- that the junction's own SELECT policy is a function call (not a
-- self-join), the subquery would actually work — but routing it
-- through the helper is cleaner and consistent, and keeps the
-- RLS-bypass semantic explicit.

drop policy if exists "playdates_select_participants_via_junction"
  on public.playdates;

create policy "playdates_select_participants_via_junction"
  on public.playdates
  for select
  using (
    public.user_is_playdate_participant(id, auth.uid())
  );

-- Nudge PostgREST to pick up the updated policies immediately rather
-- than waiting for the next schema-cache refresh.
notify pgrst, 'reload schema';
