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
In progress
