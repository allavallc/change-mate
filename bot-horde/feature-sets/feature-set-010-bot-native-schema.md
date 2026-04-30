# [feature-set-010] Bot-native schema additions

## Goal
Extend the Bot Horde ticket format with structured fields and conventions that express bot-era concerns — decomposition lineage, verification level, failure mode, dependency readiness, model provenance — and add CI validation to enforce them. The whole change ships as additions to existing markdown plus one validator script. No daemon, no scheduler, no new runtime.

## Rationale
Feedback ("v3.0") proposed a category-redefining bot-native tracker. Most of the proposal required infrastructure and broke the files-and-git contract that makes Bot Horde small. A subset — the schema-only items — is implementable as additions to the existing markdown format with no platform jump. This feature set ships exactly that subset, plus a validator that makes the new fields trustworthy.

The platform-scale items (capability matching, scheduling, cross-repo coordination, lease daemons) are deferred to a separate exploration doc and are not work in this repo.

## Tickets
- BH-071 — `Split-from:` field for ticket decomposition
- BH-072 — `Verification:` field separate from `Status:`
- BH-073 — `Failure-mode:` field on blocked tickets
- BH-074 — Commit-message provenance convention
- BH-075 — Dependency enforcement: render + filter
- BH-076 — `validate.py` enforcing the schema in CI (depends on the four field tickets and the dependency-enforcement ticket)

## Build order
BH-071, BH-072, BH-073, BH-075 land first in any order — each is independent. BH-074 can land any time (pure docs). BH-076 lands last because it enforces the fields the others introduce.

## Status
Backlog

## Notes
- The two leftover v2.0 picks (lite stale-claim render, polling honesty) are intentionally **not** in this feature set — they're independent of the schema redesign. Queued separately.
- v3.0 daemon-scale items deferred to a separate direction-setting doc; tracked outside this repo.
- The bet: five small schema additions + one validator can move HoB meaningfully toward bot-native operation without becoming a platform. If the schema additions feel decorative six months in (nobody updating Verification, every blocked ticket marked needs-human), revisit.
