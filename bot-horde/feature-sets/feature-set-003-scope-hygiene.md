# [feature-set-003] Scope & footprint hygiene

## Goal
Make it mechanically clear that Bot Horde is dev workflow tooling, not product code — through explicit scope docs, folder consolidation, install-time deploy-ignore defaults, and a quieter CI workflow.

## Rationale
An adopter running Bot Horde inside a production monorepo (hana-core) reported that Bot Horde files leaked into their mental model of product code, caused deploy-pipeline anxiety, and created noise commits on `main`. Root cause: Bot Horde's files are scattered across repo root and the docs don't explicitly mark the project as dev-only. This feature set hardens the line between "Bot Horde (dev workflow)" and "product code" through four coherent changes. Bundled because BH-050 depends on BH-049, and BH-048 documents the rule that BH-049/050/051 make enforceable.

## Tickets
- BH-048 — Scope, dependency, and LLM guardrails in BOTHORDE.md
- BH-049 — Consolidate Bot Horde footprint into bot-horde/ folder
- BH-050 — setup.sh writes deploy-ignore defaults for bot-horde/
- BH-051 — Board rebuild workflow: mode-aware auto-commit + rename

## Status
Done — 2026-04-24

## Outcome
Shipped. Repo root is now `bot-horde/` + `setup.sh` only; all dev tooling lives under the folder. BOTHORDE.md opens with explicit scope, one-way-dependency, sync-mode, and LLM-guidance blocks. setup.sh has an idempotent legacy-migration branch for existing adopters and appends `bot-horde/` to any existing `.dockerignore` / `.gcloudignore` / `.vercelignore` plus a dev-only-tooling marker to `.gitignore`. The board-rebuild workflow was renamed `Bot Horde-rebuild-board.yml` and now auto-commits only when `auto_commit_board` resolves to true (mode-aware default: team mode on, solo mode off). Breaking changes: GitHub Pages URL rename from `/bot-horde-board.html` to `/bot-horde/board.html`; solo adopters without Supabase see the quiet default. 77-test pytest suite passes throughout.
