-- 0003_locks_select_policy.sql — allow anon/authenticated to read locks (CM-012).
--
-- The board needs to query the locks table to show which agent is actively
-- working on a ticket. Lock data (ticket_id, agent name, timestamp) is not
-- sensitive — it's the same info visible on the board itself.
--
-- Idempotent: safe to re-run.

begin;

drop policy if exists locks_select_all on public.locks;
create policy locks_select_all
  on public.locks
  for select
  to anon, authenticated
  using (true);

grant select on public.locks to anon, authenticated;

commit;
