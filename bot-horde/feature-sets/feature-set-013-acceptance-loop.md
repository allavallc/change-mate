# [feature-set-013] Acceptance loop

## Goal
Close the dev → done loop with a tester signoff on user-facing tickets. Today the dev bot self-grades: it moves work from `in-progress/` to `done/` and sets `**Verification**` to whatever it picked. There is no folder, no field, and no required artifact representing "this needs a separate eyes-on pass before it ships." This feature set adds one new state, one new schema field, one new ticket section, and a tester role — and wires them to the existing `Verification` field, which until now has been orphaned.

## Rationale
Feature-set-010 introduced `**Verification**` with values `bot-claimed | tests-passed | bot-reviewed | human-reviewed`, but nothing in the workflow produces the last two — they're set passively. A unit test passing isn't the same as a human (or a tester-role bot) confirming a UI change is acceptable. This feature set adds the missing stage: user-facing tickets pause in `in-review/`, a separate tester reads `## How to test`, executes, and either approves (→ `done/`, Verification upgraded) or rejects (→ `in-progress/` with the existing `Rejected by` / `Rejection reason` fields).

Granularity is per-ticket, not per-feature-set: a feature set bundles tickets of mixed user-facing-ness (fs-010 had schema + validator + docs). `blocked/` is not reused — that means "stuck on something broken," not "complete pending external check."

Platform-scale review-queue features (assignment routing, SLA tracking, capability matching) stay out of scope. This is files-and-git: tickets sit in `in-review/`; any tester picks one up by reading the folder.

## Tickets
- BH-080 — `bot-horde/in-review/` folder + board column + filter dropdown entry
- BH-081 — `**User-facing**: yes/no` field added to ticket schema (default `no`; opt-in per ticket)
- BH-082 — `## How to test` section added to ticket format; required when `User-facing: yes`
- BH-083 — Workflow update in `BOTHORDE.md`: handoff step (in-progress → in-review for user-facing tickets), acceptance step (in-review → done), rejection path (in-review → in-progress with rejection fields)
- BH-084 — Acceptance step writes `Verification: human-reviewed` or `bot-reviewed`; the field becomes the output of this loop instead of self-set by the dev bot
- BH-085 — New `acceptance-tester` skill (sibling to `product-manager`): walks a bot through reading `## How to test`, executing the steps, and recording approve/reject + notes
- BH-086 — Commit-provenance trailers extended: `Trigger: BH-XXX accepted` / `BH-XXX rejected` added to the convention in BOTHORDE.md
- BH-087 — `validate.py` enforces the new fields: `## How to test` non-empty when `User-facing: yes`; tickets in `in-review/` carry `User-facing: yes` and `## How to test`; `Verification` value matches the path that produced the done state (rejected dev-self-set values on user-facing tickets)

## Build order
BH-080, BH-081, BH-082 ship first in any order — independent schema additions. BH-083 once the schema is in place. BH-084 after BH-083 (workflow needs the new state). BH-085 after BH-083 (the skill executes the documented workflow). BH-086 anytime (pure docs convention). BH-087 last — it enforces everything else.

## Status
Done

## Notes
- **Tester ≠ dev bot.** A bot may play the tester role, but it must be a different invocation/persona than the one that built the ticket. Self-approval defeats the purpose. BH-085 enforces this.
- **Existing done tickets stay legacy.** Validator only enforces new fields on tickets created after the schema lands. The ~38 existing `done/` tickets keep their `bot-claimed` / `tests-passed` values. No backfill.
- **`Verification` is no longer orphaned.** `human-reviewed` / `bot-reviewed` become outputs of the acceptance step. `bot-claimed` and `tests-passed` remain valid for tickets where `User-facing: no` — internal refactors skip the loop.
- **The bet.** A separate acceptance stage catches the bug where a unit-test-passing change ships a broken UX. If `User-facing: yes` is rarely set or testers always rubber-stamp, the loop is decorative — revisit then.
