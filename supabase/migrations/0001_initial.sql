-- 0001_initial.sql — change-mate initial schema
--
-- Tables:
--   locks          atomic ticket claim (one row per in-progress ticket)
--   ticket_events  append-only audit log of status transitions
--   write_keys     SHA-256 hashes of keys that authorise writes via the cm-write Edge Function
--
-- RLS: strict. anon may only SELECT ticket_events. All writes go through the
-- service-role Edge Function. locks and write_keys are invisible to anon.
--
-- Idempotent: safe to re-run against an already-migrated database.

begin;

-- ============================================================
-- locks
-- ============================================================
create table if not exists public.locks (
  ticket_id   text        primary key,
  agent       text        not null,
  started_at  timestamptz not null default now()
);

-- ============================================================
-- ticket_events
-- ============================================================
create table if not exists public.ticket_events (
  id           bigserial   primary key,
  ticket_id    text        not null,
  from_status  text,
  to_status    text        not null,
  actor        text        not null,
  created_at   timestamptz not null default now()
);

create index if not exists ticket_events_ticket_id_idx
  on public.ticket_events (ticket_id);

create index if not exists ticket_events_created_at_idx
  on public.ticket_events (created_at desc);

-- ============================================================
-- write_keys
-- ============================================================
create table if not exists public.write_keys (
  key_hash    text        primary key,
  label       text        not null,
  role        text        not null check (role in ('human', 'agent')),
  created_at  timestamptz not null default now(),
  revoked_at  timestamptz
);

create index if not exists write_keys_role_idx
  on public.write_keys (role)
  where revoked_at is null;

-- ============================================================
-- Row Level Security
-- ============================================================
alter table public.locks          enable row level security;
alter table public.ticket_events  enable row level security;
alter table public.write_keys     enable row level security;

alter table public.locks          force  row level security;
alter table public.ticket_events  force  row level security;
alter table public.write_keys     force  row level security;

-- ticket_events: anon + authenticated may SELECT. No other policies → all
-- writes denied for non-service-role. Service role bypasses RLS.
drop policy if exists ticket_events_select_all on public.ticket_events;
create policy ticket_events_select_all
  on public.ticket_events
  for select
  to anon, authenticated
  using (true);

-- locks: no policies → anon + authenticated denied on all operations.
-- Service role bypasses RLS and is the only writer (via CM-006 Edge Function).

-- write_keys: no policies → anon + authenticated denied on all operations.
-- Service role only.

-- ============================================================
-- Defense-in-depth table grants
-- Supabase grants SELECT/INSERT/UPDATE/DELETE on public tables to anon and
-- authenticated by default. RLS already gates them, but revoking the
-- table-level privilege removes ambiguity and surfaces misconfiguration
-- earlier (a permission_denied error instead of a silent empty result).
-- ============================================================
revoke all on public.locks       from anon, authenticated;
revoke all on public.write_keys  from anon, authenticated;

revoke insert, update, delete on public.ticket_events from anon, authenticated;
grant  select on public.ticket_events to anon, authenticated;

commit;
