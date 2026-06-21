-- Home/display currency preference for Stats aggregation.
-- NULL = "Auto" (fall back to the most-recent session's currency, the prior
-- behavior). Used as the default display currency everywhere money is summed
-- across mixed-currency sessions. Inherits the existing `profiles` table
-- grants/RLS — no new GRANT needed (adding a column to an already-granted
-- table; see the GRANTs gotcha in CLAUDE.md — that applies to NEW tables).
alter table public.profiles
  add column if not exists display_currency text;
