# change-mate — Claude notes

## Resuming a session

If you're a Claude agent reading this at session start, check `~/.claude/projects/<this-project>/memory/MEMORY.md` for the resume-point memory — active tickets mid-flight (including pending pre-build interviews) live there.

Authoritative workflow spec: `change-mate/CHANGEMATE.md`. Read it before touching tickets.

## Board

- `change-mate/board.html` is auto-rebuilt by GitHub Actions (`.github/workflows/change-mate-rebuild-board.yml`) on every push to `main`; rebuild commit is gated by `auto_commit_board` in `change-mate/config.json` (default `true`) — **never** run `bash change-mate/build.sh` manually and commit its output
- `change-mate/build.sh` requires Python 3 (`py` / `python3` / `python`)
- Local builds for verification are fine as long as you `git checkout -- change-mate/board.html` before committing
- Tests run in GitHub Actions (`.github/workflows/test.yml`) on push + PR

## Config

- `change-mate/config.json` holds `project_name`, optional `poll_seconds` (default 30), optional `auto_commit_board` (default true)
- Auth is GitHub — users authenticate with their own fine-grained PAT (`Contents: Read and write` on the repo). PAT lives in browser localStorage; never sent to any server other than `api.github.com`.
- No backend. Add Story PUTs directly to GitHub Contents API. Live updates come from polling `GET /repos/{owner}/{repo}/commits/main`.

## Code layout

- `change-mate/CHANGEMATE.md` — workflow spec (single source of truth)
- `change-mate/INSTALL-FAQ.md` — install-time questions (CLAUDE.md import semantics, public-repo exposure, Pages caveats, PAT scope, polling, idempotency)
- `change-mate/UPDATING.md` — bot-readable update procedure (also embedded as a section in CHANGEMATE.md)
- `change-mate/MANIFEST.json` — version map of every managed file. Drives `CHANGEMATE_CHECK_UPDATES=yes` and `CHANGEMATE_UPGRADE_DOCS=yes` in setup.sh. Bump file's entry whenever you touch it.
- `skills/product-manager/SKILL.md` — PM skill (source; `setup.sh` installs to `~/.claude/skills/product-manager/`). Has a `version:` line in frontmatter; bump on behavior change.
- `change-mate/build.sh` — generates `change-mate/board.html` (detects GitHub repo, embeds head SHA + poll config, parses all tickets, emits HTML+CSS+JS, pre-render pass computes inverse blocked-by edges and warns on orphans/cycles). Includes the `cm-poll` script (polls GitHub commits API for live board updates; **disabled on `file://`** because the local file isn't auto-updated, so reload would just re-render the same stale snapshot), the per-agent walking-robot animation, and the filter/sort bar (single-select Priority/Effort/Feature-set + Sort dropdowns, state in `localStorage` under `cm_board_filters_v1`, applied per-column inside `render()` via `filterAndSort` — stable sort with original-index tie-break).
- `change-mate/build_lib.py` — `parse_ticket` + `parse_feature_set`
- `change-mate/backlog/|in-progress/|done/|blocked/|not-doing/` — ticket files (markdown, `CM-XXX-<timestamp>.md`)
- `change-mate/feature-sets/` — feature set files (`feature-set-XXX-<slug>.md`)
- `tests/` — pytest suite (`test_parser.py` unit + `test_build.py` subprocess integration). No Supabase tests — that whole layer is gone.

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
- When you edit any file in `MANIFEST.json`'s `files` map, bump that file's value (ISO 8601 timestamp like `2026-04-27T19:35:00Z`) and update the top-level `updated`. Otherwise existing adopters won't detect the change.
- `change-mate/CHANGEMATE.md` is loaded by every Claude Code session via `@-import` — keep it lean. New verbose docs go in `INSTALL-FAQ.md` or `UPDATING.md` and get referenced from CHANGEMATE.md.
- The board is brutalist-styled per `plan/style-guide.md` (SimplifyOps system). Single rust accent (`#c4724a`); status uses dash patterns, not colors. Per-agent crab + robot colors are an intentional styleguide deviation documented in CM-060.
- Card titles + feature-set chip + modal titles use `--read` (Atkinson Hyperlegible) — chosen for legibility over Big Shoulders' display-display weight. The masthead logo keeps Big Shoulders. Card layout (post-CM-069): feature-set chip top, CM-ID + Priority/Effort badges row, title, relationship chips, expanded body, crab worker in a bottom-left `card-footer`. The duplicate `.card-assignee` text is gone.
- `setup.sh` detects local-only mode via `is_local_only_mode()` (checks `.gitignore` for an exact `change-mate` / `change-mate/` line). In that mode the rebuild-board workflow is skipped on install, prompted-for-removal if already present (`CHANGEMATE_REMOVE_WORKFLOW=yes|no`), and filtered out of the `CHANGEMATE_UPGRADE_DOCS` flow. The workflow itself is also self-defending: if `change-mate/build.sh` is absent at run time it short-circuits cleanly instead of failing every push.
