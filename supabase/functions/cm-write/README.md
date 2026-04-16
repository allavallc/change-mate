# cm-write Edge Function

Creates a new change-mate ticket: validates the payload, claims the next CM-ID from a Postgres sequence, commits the markdown file to GitHub, and logs the event to `ticket_events`.

## Endpoint

```
POST https://<project-ref>.supabase.co/functions/v1/cm-write
```

## Request

```json
{
  "write_key": "your-secret-key",
  "payload": {
    "title": "Short ticket title",
    "goal": "What needs to happen.",
    "done_when": "Acceptance criteria.",
    "priority": "High",
    "effort": "M",
    "why": "Optional context.",
    "notes": "Optional notes.",
    "feature_set": "Optional feature set name."
  }
}
```

### Required fields

| Field | Type | Constraints |
|---|---|---|
| `title` | string | 1–200 chars, trimmed |
| `goal` | string | 1–10,000 chars |
| `done_when` | string | 1–10,000 chars |
| `priority` | enum | `Low`, `Medium`, `High`, `Critical` |
| `effort` | enum | `XS`, `S`, `M`, `L`, `XL` |

### Optional fields

| Field | Type | Constraints |
|---|---|---|
| `why` | string | max 10,000 chars |
| `notes` | string | max 20,000 chars |
| `feature_set` | string | max 10,000 chars |

Unknown fields are rejected (422).

## Response (200)

```json
{
  "phase": 2,
  "ticket_id": "CM-014",
  "file_path": "change-mate/backlog/CM-014-1776256496.md",
  "actor": "Key Label",
  "github_created": true,
  "commit_sha": "abc123...",
  "file_sha": "def456...",
  "html_url": "https://github.com/owner/repo/blob/main/change-mate/backlog/CM-014-1776256496.md",
  "audit_logged": true
}
```

`audit_logged` is `false` if the GitHub commit succeeded but the `ticket_events` insert failed (rare — the ticket still exists in the repo).

## Error codes

| Status | Meaning |
|---|---|
| 401 | Missing, empty, or unrecognised `write_key` |
| 403 | `write_key` has been revoked |
| 405 | Method other than POST |
| 422 | Malformed JSON or invalid payload |
| 500 | Internal failure (auth lookup, RPC, GitHub auth/conflict) |
| 502 | GitHub network or upstream server error |
| 503 | GitHub rate limited |

## Required environment variables

Set these via `supabase secrets set`:

| Variable | Description |
|---|---|
| `SUPABASE_URL` | Set automatically by Supabase |
| `SUPABASE_SERVICE_ROLE_KEY` | Set automatically by Supabase |
| `GITHUB_PAT` | Fine-grained PAT with `contents:write` on the repo |
| `GITHUB_OWNER` | GitHub username or org that owns the repo |
| `GITHUB_REPO` | Repository name (not the full URL) |
| `GITHUB_BRANCH` | *(optional)* Target branch — defaults to the repo's default branch |

## Write key management

A write key is any secret string. Only its SHA-256 hash is stored in the `write_keys` table.

**Generate a key:**
```bash
openssl rand -hex 32
```

**Insert the hash:**
```sql
insert into public.write_keys (key_hash, label, role)
values (
  encode(sha256(convert_to('YOUR_KEY', 'UTF8')), 'hex'),
  'Your Name',
  'human'   -- or 'agent'
);
```

**Revoke a key:**
```sql
update public.write_keys set revoked_at = now() where label = 'Your Name';
```

## Running tests

Requires [Deno](https://deno.land):

```bash
deno test --allow-env supabase/functions/cm-write/
```

## Deploying

```bash
supabase functions deploy cm-write
```
