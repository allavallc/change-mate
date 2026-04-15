-- supabase/tests/verify.sql
-- Deep schema verification. Paste into the Supabase SQL editor AFTER applying
-- 0001_initial.sql. On success every check prints a NOTICE; any failure raises
-- an exception with the specific check name.
--
-- Safe to re-run. Does not modify data.

do $$
begin
  -- ----- tables exist -----
  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'locks'
  ) then raise exception 'FAIL: public.locks does not exist'; end if;

  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'ticket_events'
  ) then raise exception 'FAIL: public.ticket_events does not exist'; end if;

  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'write_keys'
  ) then raise exception 'FAIL: public.write_keys does not exist'; end if;
  raise notice 'PASS: all three tables exist';

  -- ----- RLS enabled AND forced on every table -----
  if exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname in ('locks', 'ticket_events', 'write_keys')
      and (c.relrowsecurity = false or c.relforcerowsecurity = false)
  ) then raise exception 'FAIL: RLS not enabled+forced on all three tables'; end if;
  raise notice 'PASS: RLS enabled and forced on all tables';

  -- ----- ticket_events SELECT policy exists for anon -----
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'ticket_events'
      and policyname = 'ticket_events_select_all'
      and cmd = 'SELECT'
  ) then raise exception 'FAIL: ticket_events_select_all policy missing'; end if;
  raise notice 'PASS: ticket_events SELECT policy present';

  -- ----- NO policies on locks or write_keys (strict deny-all for non-service-role) -----
  if exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename in ('locks', 'write_keys')
  ) then raise exception 'FAIL: unexpected policy on locks or write_keys'; end if;
  raise notice 'PASS: locks and write_keys have zero policies (deny-all)';

  -- ----- write_keys role check constraint (human | agent) -----
  if not exists (
    select 1
    from information_schema.check_constraints cc
    join information_schema.constraint_column_usage ccu
      on cc.constraint_name = ccu.constraint_name
    where ccu.table_schema = 'public'
      and ccu.table_name = 'write_keys'
      and ccu.column_name = 'role'
      and cc.check_clause like '%human%'
      and cc.check_clause like '%agent%'
  ) then raise exception 'FAIL: write_keys.role check constraint (human|agent) missing'; end if;
  raise notice 'PASS: write_keys.role check constraint present';

  -- ----- indexes -----
  if not exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and tablename = 'ticket_events'
      and indexname = 'ticket_events_ticket_id_idx'
  ) then raise exception 'FAIL: ticket_events_ticket_id_idx missing'; end if;

  if not exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and tablename = 'ticket_events'
      and indexname = 'ticket_events_created_at_idx'
  ) then raise exception 'FAIL: ticket_events_created_at_idx missing'; end if;

  if not exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and tablename = 'write_keys'
      and indexname = 'write_keys_role_idx'
  ) then raise exception 'FAIL: write_keys_role_idx missing'; end if;
  raise notice 'PASS: all expected indexes present';

  raise notice '===== ALL VERIFICATIONS PASSED =====';
end $$;
