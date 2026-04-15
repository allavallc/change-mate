-- supabase/tests/concurrent_lock_test.sql
-- Proves the atomic claim semantics of public.locks: a second INSERT for the
-- same ticket_id must fail with unique_violation, never create a duplicate row.
--
-- Paste into the Supabase SQL editor. Cleans up after itself; leaves no rows.

do $$
declare
  duplicate_rejected boolean := false;
  row_count int;
begin
  -- Clean up any leftover from a prior aborted run
  delete from public.locks where ticket_id = 'TEST-LOCK-CONCURRENT';

  -- First claim: must succeed
  insert into public.locks (ticket_id, agent) values ('TEST-LOCK-CONCURRENT', 'agent-a');

  -- Second claim on same ticket: must fail with unique_violation
  begin
    insert into public.locks (ticket_id, agent) values ('TEST-LOCK-CONCURRENT', 'agent-b');
  exception when unique_violation then
    duplicate_rejected := true;
  end;

  if not duplicate_rejected then
    raise exception 'FAIL: second INSERT did not raise unique_violation — duplicate claim was allowed';
  end if;

  -- Exactly one row must remain
  select count(*) into row_count
  from public.locks where ticket_id = 'TEST-LOCK-CONCURRENT';
  if row_count <> 1 then
    raise exception 'FAIL: expected exactly 1 lock row, got %', row_count;
  end if;

  -- Cleanup
  delete from public.locks where ticket_id = 'TEST-LOCK-CONCURRENT';

  raise notice 'PASS: concurrent claim rejected — duplicate INSERT blocked by PK, exactly 1 row persisted';
end $$;
