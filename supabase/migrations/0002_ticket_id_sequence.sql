-- 0002_ticket_id_sequence.sql — atomic CM-ID allocation for cm-write (CM-006).
--
-- Provisions:
--   public.ticket_id_seq         bigint sequence starting at 12
--                                (max existing ticket at time of writing = CM-011)
--   public.claim_ticket_id()     security-definer helper the Edge Function calls
--                                via supabase.rpc('claim_ticket_id')
--
-- Guarantees no two concurrent writes ever receive the same CM-ID.
-- Idempotent: safe to re-run.

begin;

-- ============================================================
-- Sequence
-- ============================================================
create sequence if not exists public.ticket_id_seq
  as bigint
  start with 12
  increment by 1
  minvalue 1
  no cycle;

revoke all on sequence public.ticket_id_seq from public;
revoke all on sequence public.ticket_id_seq from anon, authenticated;

-- ============================================================
-- RPC helper (callable via supabase.rpc('claim_ticket_id'))
-- ============================================================
create or replace function public.claim_ticket_id()
returns bigint
language sql
security definer
set search_path = public
as $$
  select nextval('public.ticket_id_seq');
$$;

revoke all on function public.claim_ticket_id() from public;
revoke all on function public.claim_ticket_id() from anon, authenticated;
grant execute on function public.claim_ticket_id() to service_role;

commit;
