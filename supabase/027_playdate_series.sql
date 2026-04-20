-- 027_playdate_series.sql
-- Date: 2026-04-19
--
-- Weekly-repeat playdates (×4) — groups four playdate rows into a
-- "series" so a user composing "每周六下午 3 点在公园遛弯" once creates
-- the next month of invitations in a single gesture, instead of
-- re-opening the composer four times.
--
-- Why this shape:
--
--   * `series_id uuid` — a shared marker across the 4 sibling rows.
--     Null on one-off playdates. We mint the uuid client-side (Swift
--     `UUID()`) so a single batch of 4 inserts shares the same value
--     without an extra round-trip to `gen_random_uuid()`. Defence in
--     depth is the uuid-collision probability — 2^122 — which is
--     indistinguishable from zero at human scales.
--
--   * `series_sequence smallint` (1..4) — identifies which instance
--     within the series a given row represents. Surfaces in the UI as
--     "第 X 场 / 共 4 场" and lets the composer push the
--     `series_sequence == 1` row into detail after a successful propose
--     (the user expects to land on the *first* playdate they just
--     scheduled, not an arbitrary one). smallint (2 bytes) is plenty
--     for 4 instances and keeps the row footprint lean. Null on
--     one-offs. Storing the sequence rather than deriving it from
--     `scheduled_at` ordering means the number survives edge cases
--     like "user skipped a week" if we ever allow that — and keeps
--     the "第 2 场 / 共 4 场" label deterministic even when two
--     instances share a timestamp (shouldn't happen for weekly, but
--     cheap insurance).
--
--   * No RLS changes — existing proposer/invitee policies from
--     migration 023 already gate visibility per-row. Series membership
--     is only visible to participants of at least one instance, which
--     is the right semantic (a stranger learning "this is a series"
--     would already need to see one of the rows, which RLS forbids).
--
--   * No FK on `series_id` — it intentionally has no parent table.
--     A "series" is a bag of 4 sibling rows glued by a shared uuid,
--     not a first-class entity. Adding a `playdate_series` table with
--     a parent row would cost an extra INSERT per propose + create a
--     lifecycle question (what happens when all 4 rows are cancelled?
--     does the parent still exist?) with no benefit — every query we
--     care about ("load my series", "cancel the series") is a
--     `where series_id = $1` filter that works fine against the
--     denormalised column.
--
--   * A later task (#23, group playdates via `playdate_participants`)
--     reshapes the participant side of playdates. `series_id` is an
--     orthogonal dimension — a future group playdate can also be part
--     of a series, and the participant junction will simply have rows
--     for each of the series's playdate ids. This migration is
--     deliberately additive so it composes cleanly with whatever
--     shape the participant model takes.
--
-- Prerequisites: migration 023 must have been applied. Idempotent and
-- safe to re-apply.

-- ---------------------------------------------------------------------
-- playdates.series_id — series bag marker
-- ---------------------------------------------------------------------
alter table public.playdates
  add column if not exists series_id uuid;

comment on column public.playdates.series_id is
  'Groups playdate rows that belong to the same recurring series '
  'created from "每周重复 ×4" in the composer. Null for one-off '
  'playdates. No FK — a series is defined implicitly as the set of '
  'rows sharing this uuid.';

-- ---------------------------------------------------------------------
-- playdates.series_sequence — position within the series (1..4)
-- ---------------------------------------------------------------------
alter table public.playdates
  add column if not exists series_sequence smallint;

comment on column public.playdates.series_sequence is
  'Position within the series, 1..4. Null for one-off playdates. '
  'Surfaces in the UI as "第 X 场 / 共 4 场"; also lets the composer '
  'push the series_sequence = 1 row into the detail view after a '
  'successful propose so the user lands on the first instance.';

-- ---------------------------------------------------------------------
-- Partial index — lookups are always "all rows in series X"
-- ---------------------------------------------------------------------
-- Partial (where series_id is not null) because one-off rows vastly
-- outnumber series rows in expected workload — the index stays tiny.
create index if not exists idx_playdates_series
  on public.playdates(series_id)
  where series_id is not null;

-- ---------------------------------------------------------------------
-- Optional CHECK — sequence must be in 1..4 when present
-- ---------------------------------------------------------------------
-- Gated on a `pg_constraint` lookup so re-runs are a no-op. The check
-- allows NULL for one-offs (a CHECK returning NULL passes) and rejects
-- out-of-range values from a future client bug.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'playdates_series_sequence_range'
      and conrelid = 'public.playdates'::regclass
  ) then
    alter table public.playdates
      add constraint playdates_series_sequence_range
      check (series_sequence is null or (series_sequence between 1 and 4));
  end if;
end $$;

-- Nudge PostgREST to refresh its schema cache so the new columns are
-- immediately visible to the iOS client without a project restart.
notify pgrst, 'reload schema';
