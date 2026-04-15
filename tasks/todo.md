# CM-006 — Supabase Edge Function `cm-write` (validated ticket writes via GitHub API)

**Interview answers locked 2026-04-15** — user picked defaults (a/a/a/a/a):
- Q1 = (a) Postgres sequence for CM-ID assignment (atomic, race-free)
- Q2 = (a) Fine-grained PAT with `contents:write` on the repo only; PAT + owner + repo as Supabase secrets
- Q3 = (a) Skip rate-limiting for MVP; follow-up ticket captures it
- Q4 = (a) Payload schema as proposed (required vs optional, max sizes, enum priority + effort)
- Q5 = (a) GitHub Contents API (single PUT call per ticket)

**Dependencies**: CM-005 (schema with `write_keys` + `ticket_events`) ✅. Max existing CM-ID is 011, so sequence starts at 12.

**Status**: plan drafted — awaiting explicit **"go Phase 1"**.

---

## Phase 1 — Schema migration + function skeleton + validation + unit tests (no GitHub calls yet)

Files (≤5):
1. `supabase/migrations/0002_ticket_id_sequence.sql` — `CREATE SEQUENCE public.ticket_id_seq START 12`, revokes from `anon`+`authenticated`, plus a SECURITY DEFINER function `public.claim_ticket_id() RETURNS bigint` callable only by service role. Wrapped in `begin;...commit;`, idempotent.
2. `supabase/functions/cm-write/index.ts` — HTTP handler. Orchestrates: parse request → auth (look up SHA-256 key hash in `write_keys` where `revoked_at IS NULL`) → validate payload → call `claim_ticket_id` RPC → render markdown → insert `ticket_events` row → **stub** GitHub call (Phase 2) → respond. Error mapping: 401 invalid/missing key, 403 revoked, 422 bad payload, 500 internal.
3. `supabase/functions/cm-write/validate.ts` — pure function `validate(payload) -> {ok, payload, error?}` with enum enforcement (`Low|Medium|High|Critical`, `XS|S|M|L|XL`), size caps, unknown-field rejection.
4. `supabase/functions/cm-write/ticket.ts` — pure function `renderTicket(id: number, payload, timestamp) -> {file_path, markdown}`. Produces `change-mate/backlog/CM-NNN-<timestamp>.md` content matching existing ticket format.
5. `supabase/functions/cm-write/_test.ts` — Deno tests covering: every validation branch, every error code, ticket rendering golden-file, plus a mocked end-to-end happy path (supabase-js + RPC stubbed).

**Verification after Phase 1**:
- Apply `0002_ticket_id_sequence.sql` in Supabase SQL editor → `select public.claim_ticket_id();` returns `12`, next call returns `13`, anon cannot call it
- `deno test supabase/functions/cm-write/` green
- `py -m pytest` still green (34 + 19 + 11 = 64)
- Add a static-analysis pytest covering migration 0002 (same pattern as `test_migration_sql.py`)

## Phase 2 — GitHub integration + end-to-end

Files (≤5):
1. `supabase/functions/cm-write/github.ts` — thin wrapper around `PUT /repos/{owner}/{repo}/contents/{path}` using `GITHUB_PAT`, `GITHUB_OWNER`, `GITHUB_REPO` env vars. Returns commit SHA + file SHA on success; typed errors for rate limit / auth / unknown.
2. `supabase/functions/cm-write/index.ts` — replace Phase 1 stub with real call to `github.ts`. On GitHub failure, **do NOT** leave a `ticket_events` row behind — use a transaction or compensating delete.
3. `supabase/functions/cm-write/_test.ts` — expand: mock fetch for GitHub API (success, 401, 422, 5xx), assert rollback of `ticket_events` on failure.
4. Deno import map / `deno.json` at `supabase/functions/` if one doesn't exist yet, to pin supabase-js + std versions.

**Verification after Phase 2**:
- Local Deno test suite green against all mocks
- Manual smoke test: hit deployed function with a real write key + real payload → verify a new `change-mate/backlog/CM-012-<ts>.md` file appears in the repo and one `ticket_events` row exists
- Negative smoke test: invalid key → 401 + no ticket_events row

## Phase 3 — Deploy docs + secrets wiring + SETUP.md update

Files (≤5):
1. `SETUP.md` — new section "Step 2.6 — Deploy the cm-write Edge Function (optional until Add-Story is used)": install Supabase CLI, `supabase login`, `supabase link --project-ref`, `supabase secrets set GITHUB_PAT=... GITHUB_OWNER=... GITHUB_REPO=...`, `supabase functions deploy cm-write`, smoke-test with `curl`. Also write-key generation SQL (small enough to land here instead of a separate script).
2. `supabase/functions/cm-write/README.md` — function-level doc: input schema, output schema, error codes, required env vars, how to roll a key.

**Verification after Phase 3**:
- Read SETUP.md cold — a new user could deploy from zero without asking questions
- Integration smoke test passes end-to-end

---

## Out of scope (spinoff tickets)
- **Rate limiting** — defer to a new ticket (CM-012 or later). Document the gap at the end of CM-006.
- **Write-key generation CLI** — CM-007 already scoped to cover the UX. SETUP.md gets a manual SQL fallback in Phase 3.
- **Concurrency stress test (10 parallel writes)** — sequence design makes this trivially correct; covered by unit test on `claim_ticket_id`, skip true load test.
- **Frontend wiring of Add Story → cm-write** — CM-007.
