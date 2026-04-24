# change-mate — Claude notes

## Resuming a session

If you're a Claude agent reading this at session start, check `~/.claude/projects/<this-project>/memory/MEMORY.md` for the resume-point memory — active tickets mid-flight (including pending pre-build interviews) live there.

Authoritative workflow spec: `change-mate/CHANGEMATE.md`. Read it before touching tickets.

## Board

- `change-mate/board.html` is auto-rebuilt by GitHub Actions (`.github/workflows/build-board.yml`) on every push to `main` — **never** run `bash change-mate/build.sh` manually and commit its output
- `change-mate/build.sh` requires Python 3 (`py` / `python3` / `python`)
- Local builds for verification are fine as long as you `git checkout -- change-mate/board.html` before committing
- Tests run in GitHub Actions (`.github/workflows/test.yml`) on push + PR

## Config

- `change-mate/config.json` holds `gist_id`, `project_name`, `supabase_url`, `supabase_publishable_key`
- GitHub Actions secrets: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`
- Auth is GitHub — users authenticate with their own GitHub token (fine-grained PAT with `contents:write` on the repo). The cm-write Edge Function verifies push access via GitHub API. No separate key/password system.
- Supabase secrets for cm-write: `GITHUB_PAT`, `GITHUB_OWNER`, `GITHUB_REPO` (set once via `supabase secrets set`)

## Code layout

- `change-mate/CHANGEMATE.md` — workflow spec (single source of truth)
- `skills/product-manager/SKILL.md` — PM skill (source; `setup.sh` installs to `~/.claude/skills/product-manager/`)
- `change-mate/build.sh` — generates `change-mate/board.html` (embeds Supabase creds, detects GitHub repo, parses all tickets, emits HTML+CSS+JS, pre-render pass computes inverse blocked-by edges and warns on orphans/cycles)
- `change-mate/build_lib.py` — `parse_ticket` + `parse_feature_set`
- `change-mate/backlog/|in-progress/|done/|blocked/|not-doing/` — ticket files (markdown, `CM-XXX-<timestamp>.md`)
- `change-mate/feature-sets/` — feature set files (`feature-set-XXX-<slug>.md`)
- `tests/` — pytest suite (`test_parser.py` unit + `test_build.py` subprocess integration)

## Ticket format — quick reference

Every ticket has: `**Status**`, `**Priority**`, `**Effort**`, `**Feature set**`, optional `**Related**` / `**Blocks**` / `**Blocked by**` (comma-separated CM-IDs), assignee + dates, then `## Goal`, `## Why`, `## Done when`, `## Desired output`, `## Success signals`, `## Failure signals`, `## Tests`, `## Notes`. Legacy tickets without new sections still parse — do not backfill unless asked.

Relationships: **write only one side of each edge.** The renderer infers the inverse at build time.

## Commands

| Task | Command |
|---|---|
| Run tests locally | `py -m pytest -v` (or `pytest -v` on Linux/Mac) |
| Build board locally (reset before commit) | `bash change-mate/build.sh && git checkout -- change-mate/board.html` |
| Install PM skill globally | `bash setup.sh` (part of setup flow) |

## Gotchas

- Windows CRLF: `.gitattributes` enforces LF on `*.sh` / `*.py` / `*.yml`. If `test_build.py` fails locally with `$'\r'` errors, `sed -i 's/\r$//' change-mate/build.sh` fixes it. CI is unaffected.
- `change-mate/build.sh` embedded JS uses `\\` escape convention (double-backslash in source → single-backslash in generated JS). Preserve this when editing regex patterns inside the JS block.
- Feature set IDs must be unique — two files both starting `feature-set-001-` will collide.
