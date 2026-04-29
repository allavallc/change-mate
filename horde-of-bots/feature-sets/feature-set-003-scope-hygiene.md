# [feature-set-003] Scope & footprint hygiene

## Goal
Make it mechanically clear that change-mate is dev workflow tooling, not product code — through explicit scope docs, folder consolidation, install-time deploy-ignore defaults, and a quieter CI workflow.

## Rationale
An adopter running change-mate inside a production monorepo (hana-core) reported that change-mate files leaked into their mental model of product code, caused deploy-pipeline anxiety, and created noise commits on `main`. Root cause: change-mate's files are scattered across repo root and the docs don't explicitly mark the project as dev-only. This feature set hardens the line between "change-mate (dev workflow)" and "product code" through four coherent changes. Bundled because CM-050 depends on CM-049, and CM-048 documents the rule that CM-049/050/051 make enforceable.

## Tickets
- CM-048 — Scope, dependency, and LLM guardrails in CHANGEMATE.md
- CM-049 — Consolidate change-mate footprint into change-mate/ folder
- CM-050 — setup.sh writes deploy-ignore defaults for change-mate/
- CM-051 — Board rebuild workflow: mode-aware auto-commit + rename

## Status
Done — 2026-04-24

## Outcome
Shipped. Repo root is now `change-mate/` + `setup.sh` only; all dev tooling lives under the folder. CHANGEMATE.md opens with explicit scope, one-way-dependency, sync-mode, and LLM-guidance blocks. setup.sh has an idempotent legacy-migration branch for existing adopters and appends `change-mate/` to any existing `.dockerignore` / `.gcloudignore` / `.vercelignore` plus a dev-only-tooling marker to `.gitignore`. The board-rebuild workflow was renamed `change-mate-rebuild-board.yml` and now auto-commits only when `auto_commit_board` resolves to true (mode-aware default: team mode on, solo mode off). Breaking changes: GitHub Pages URL rename from `/change-mate-board.html` to `/change-mate/board.html`; solo adopters without Supabase see the quiet default. 77-test pytest suite passes throughout.
