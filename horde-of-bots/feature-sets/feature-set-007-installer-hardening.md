# [feature-set-007] Installer hardening

## Goal
Address the gaps a careful first-time adopter hit while reading `setup.sh` + `SETUP.md`. Ship the missing files, support non-interactive installs, mark the CLAUDE.md import so it isn't silently broken, fix README accuracy, and document the install-time questions adopters have so they don't have to ask.

## Rationale
A user reviewing the install before running it found a real install-blocker (build.sh + workflow not actually downloaded by setup.sh), several non-interactive-install hazards, and a long list of clarifying questions about behavior. Most of the clarifications are answerable but live nowhere in the repo today; they get asked over and over. This feature set turns the answers into either code (when there's a fix) or a single FAQ file the agent + adopter read at install time.

## Tickets
- CM-061 — setup.sh actually installs the runtime files (build.sh, build_lib.py, workflow, config.json)
- CM-062 — Non-interactive install path (`CHANGEMATE_AUTO_MIGRATE=yes` env / piped-stdin support)
- CM-063 — "Do not edit" markers around the CLAUDE.md import block
- CM-064 — README + docs honesty pass (Python 3 dep, no "zero deps" claim, Pages caveats)
- CM-065 — Version pin + upgrade path for the product-manager skill
- CM-066 — `change-mate/INSTALL-FAQ.md` covering the questions setup.sh can't answer in code

## Status
Done — 2026-04-27

## Outcome
Shipped. setup.sh now installs the runtime files (build.sh, build_lib.py, workflow YAML, config, INSTALL-FAQ.md) — no more "build.sh not found" after install. Non-interactive installs work via `CHANGEMATE_AUTO_MIGRATE=yes` and `CHANGEMATE_UPGRADE_SKILL=yes` env vars + TTY detection. The CLAUDE.md import is now wrapped in `<!-- change-mate import block -->` markers and idempotently re-applied. README + SETUP no longer claim "zero deps" (Python 3 stated up front) and warn about public-board exposure on Pages. The PM skill has a `version: 1.0.0` line; setup.sh diffs local vs upstream and prompts for upgrade. New `change-mate/INSTALL-FAQ.md` answers the 10 install-time questions adopters keep asking and is downloaded automatically. 35 tests pass.
