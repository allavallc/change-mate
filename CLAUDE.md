# change-mate — Claude notes

## Resuming a session

If you're a Claude agent reading this at session start, check `~/.claude/projects/<this-project>/memory/MEMORY.md` for the resume-point memory — active tickets mid-flight (including pending pre-build interviews) live there.

Authoritative workflow spec: `CHANGEMATE.md`. Read it before touching tickets.

## Board

- `change-mate-board.html` is auto-rebuilt by GitHub Actions (`.github/workflows/build-board.yml`) on every push to `main` — **never** run `bash build.sh` manually and commit its output
- `build.sh` requires Python 3 (`py` / `python3` / `python`)
- Local builds for verification are fine as long as you `git checkout -- change-mate-board.html` before committing
- Tests run in GitHub Actions (`.github/workflows/test.yml`) on push + PR

## Config

- `change-mate-config.json` holds `gist_id`, `project_name`, `supabase_url`, `supabase_publishable_key`
- GitHub Actions secrets: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`
- Live Gist lock registry (legacy) requires `CHANGEMATE_GITHUB_TOKEN` env var — being replaced in feature-set-001 (Supabase upgrade)

## Code layout

- `CHANGEMATE.md` — workflow spec (single source of truth)
- `skills/product-manager/SKILL.md` — PM skill (source; `setup.sh` installs to `~/.claude/skills/product-manager/`)
- `build.sh` — generates `change-mate-board.html` (embeds Supabase creds, detects GitHub repo, parses all tickets, emits HTML+CSS+JS, pre-render pass computes inverse blocked-by edges and warns on orphans/cycles)
- `build_lib.py` — `parse_ticket` + `parse_feature_set`
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
| Build board locally (reset before commit) | `bash build.sh && git checkout -- change-mate-board.html` |
| Install PM skill globally | `bash setup.sh` (part of setup flow) |

## Gotchas

- Windows CRLF: `.gitattributes` enforces LF on `*.sh` / `*.py` / `*.yml`. If `test_build.py` fails locally with `$'\r'` errors, `sed -i 's/\r$//' build.sh` fixes it. CI is unaffected.
- `build.sh` embedded JS uses `\\` escape convention (double-backslash in source → single-backslash in generated JS). Preserve this when editing regex patterns inside the JS block.
- Feature set IDs must be unique — two files both starting `feature-set-001-` will collide.
