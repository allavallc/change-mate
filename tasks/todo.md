# CM-005 — Pre-build interview (AWAITING USER ANSWERS)

**Status**: interview drafted, user will return tomorrow (2026-04-14 → 2026-04-15) to answer Q1–Q5. Do not start any phase work until these are resolved.

## What I understand the work to be

1. Create a single idempotent SQL migration file (suggested: `supabase/migrations/0001_initial.sql`) that provisions:
   - `locks` — `ticket_id` (PK, text), `agent` (text), `started_at` (timestamptz), atomic claim via PK uniqueness
   - `ticket_events` — `id` (bigint/uuid PK), `ticket_id` (text, indexed), `from_status`, `to_status`, `actor`, `created_at`
   - `write_keys` — `key_hash` (PK), `label`, `role` (human | agent), `created_at`, `revoked_at`
2. RLS policies:
   - `ticket_events`: anon can `select`, only service role can `insert`
   - `locks`: only service role can `insert` / `delete` (agents call through `cm-write` Edge Function in CM-006)
   - `write_keys`: readable only by service role
3. Idempotent provisioning — safe to re-run the SQL
4. SQL assertions (or pgTap) that verify RLS behaves

## Open questions — must resolve before any code

### Q1 — Supabase project status (blocks everything)
- a) Project exists, you'll apply the SQL via the Supabase SQL editor after I write it
- b) No project yet — ticket delivers just the SQL file + README instructions; provisioning later
- c) Project exists and you want me to apply via the Supabase CLI (needs credentials / access)

### Q2 — Direct-write vs always-through-Edge-Function
- a) **Strict — all writes through `cm-write` Edge Function (CM-006)**. Anon cannot insert into `locks` or `ticket_events` directly. CM-006 must ship before CM-008 can function. (Claude's recommendation.)
- b) Loose — allow anon inserts to `locks` gated by publishable key, as a transitional measure for faster parallel progress on CM-008
- c) Write the RLS strict now, revisit if CM-008 actually needs looser rules

### Q3 — Key hashing algorithm for `write_keys.key_hash`
- a) **SHA-256 of plaintext** (Claude's rec — keys are machine-generated high-entropy, not user-chosen passwords)
- b) Bcrypt — over-engineered here but future-proof
- c) Plain SHA-256 + aggressive rotation policy

### Q4 — `ticket_events` retention
- a) **Forever** (Claude's rec — small audit log, negligible storage)
- b) Cap at 90 days or 10k rows

### Q5 — Migration file organization
- a) **Single `0001_initial.sql` with everything** (Claude's rec — cleaner for initial provisioning, split later when real migrations come)
- b) Three files: `0001_locks.sql`, `0002_ticket_events.sql`, `0003_write_keys.sql`

## Shortcut

If you just want to proceed with all recommendations: say "defaults" and we use Q1 answer-required, Q2 (a), Q3 (a), Q4 (a), Q5 (a). Q1 still needs a direct pick — it can't be a default.

## Once Q1–Q5 are answered

I'll write the phased plan into this file (estimate: 2–3 phases, ≤5 files each) and wait for "go Phase 1".
