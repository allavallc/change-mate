# CM-005 — Supabase schema (locks, ticket_events, write_keys + RLS)

**Status**: all three phases delivered and verified against a live Supabase project on 2026-04-15. Ticket still physically in `change-mate/backlog/` — awaiting user go-ahead to move to `done/`.

## Interview answers (locked 2026-04-15)
- Q1 = (a) Supabase project exists — user applies SQL via Supabase SQL editor
- Q2 = (a) Strict RLS — all writes via `cm-write` Edge Function (CM-006)
- Q3 = (a) SHA-256 of plaintext for `write_keys.key_hash`
- Q4 = (a) `ticket_events` retained forever
- Q5 = (a) Single `0001_initial.sql` with everything
- Scope addition: `SETUP.md` at repo root, write-key generation deferred to CM-006

## Delivered

### Phase 1 — Migration SQL
- `supabase/migrations/0001_initial.sql` — three tables, RLS enabled + forced, strict policies, defense-in-depth revokes, wrapped in `begin; ... commit;`, fully idempotent

### Phase 2 — Verification
- `supabase/tests/verify.sql` — deep schema assertions (tables, RLS flags, policies, indexes, check constraint) — paste in SQL editor
- `supabase/tests/concurrent_lock_test.sql` — atomic claim proof via duplicate insert → unique_violation
- `tests/test_migration_sql.py` — 11 static-analysis tests, always runs in CI, no database needed
- `tests/test_verify_supabase.py` — 19 tests for the verify script (mocked urllib, covers config loading, retry logic, every check path, every main exit code)
- `tests/conftest.py` — adds scripts/ + repo root to sys.path for tests

### Phase 3 — Onboarding (pulled forward into Phase 1)
- `SETUP.md` at repo root — 5-step grandma-grade flow (create project → apply schema → wire up config → verify schema → verify RLS); includes "Enable Data API" step and troubleshooting for PGRST002
- `scripts/verify_supabase.py` — pure-stdlib Python, reads `change-mate-config.json`, probes three REST endpoints, retries transparently on PGRST002, distinct exit path for schema-cache-cold diagnosis
- `README.md` — "Setup" section replaced with link to SETUP.md (single source of truth)

## Verification against live project (2026-04-15)
- Migration applied via Supabase SQL editor — idempotent, re-ran cleanly
- `py scripts/verify_supabase.py` — all three `[PASS]`
- Hit and recovered from PGRST002 caused by Data API being disabled by default on new Supabase projects — root cause documented in SETUP.md and troubleshooting table
- Full pytest suite: 64/64 green (up from 34 at session start)

## Not in scope (downstream tickets)
- `cm-write` Edge Function → CM-006
- Write-key generation helper → CM-006 / CM-007
- Migrating existing Gist lock data → CM-008
- Frontend wiring to read `ticket_events` → CM-009

## Awaiting
User decision on moving `change-mate/backlog/CM-005-1776184900.md` to `change-mate/done/`.
