# cm-write Edge Function

Creates a new change-mate ticket. Validates the payload, claims the next CM-ID, commits the markdown file to GitHub, logs the event, and broadcasts to the live board.

## Auth

Uses GitHub as the auth layer. The caller sends their own GitHub token. The function verifies they have push access to the repo. No separate keys or passwords.

## Endpoint

```
POST https://<project-ref>.supabase.co/functions/v1/cm-write
```

## Request

```json
{
  "github_token": "github_pat_...",
  "actor_name": "crabFather",
  "payload": {
    "title": "Short ticket title",
    "goal": "What needs to happen.",
    "done_when": "Acceptance criteria.",
    "priority": "High",
    "effort": "M"
  }
}
```

`actor_name` is optional — defaults to the GitHub username from the token.

### Required payload fields

| Field | Type | Constraints |
|---|---|---|
| `title` | string | 1–200 chars |
| `goal` | string | 1–10,000 chars |
| `done_when` | string | 1–10,000 chars |
| `priority` | enum | `Low`, `Medium`, `High`, `Critical` |
| `effort` | enum | `XS`, `S`, `M`, `L`, `XL` |

### Optional payload fields

| Field | Type | Constraints |
|---|---|---|
| `why` | string | max 10,000 chars |
| `notes` | string | max 20,000 chars |
| `feature_set` | string | max 10,000 chars |

## Response (200)

```json
{
  "ticket_id": "CM-014",
  "file_path": "change-mate/backlog/CM-014-1776256496.md",
  "actor": "crabFather",
  "github_created": true,
  "commit_sha": "abc123...",
  "file_sha": "def456...",
  "html_url": "https://github.com/..."
}
```

## Error codes

| Status | Meaning |
|---|---|
| 401 | Missing github_token |
| 403 | Token doesn't have push access to the repo |
| 405 | Not POST |
| 422 | Bad JSON or invalid payload |
| 500 | Internal error |
| 502 | GitHub upstream error |
| 503 | GitHub rate limited |

## Required secrets

Set via `supabase secrets set`:

| Variable | What it is |
|---|---|
| `GITHUB_PAT` | Server-side PAT for committing files |
| `GITHUB_OWNER` | GitHub username or org |
| `GITHUB_REPO` | Repository name |

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are set automatically by Supabase.

## Running tests

```bash
deno test --allow-env supabase/functions/cm-write/
```

## Deploying

```bash
supabase functions deploy cm-write --no-verify-jwt
```
