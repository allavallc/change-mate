# [feature-set-011] Board honesty

## Goal
Stop the board from pretending to know things it doesn't. Surface staleness on in-progress cards so humans + bots can act on dead claims; make the polling story honest so non-GitHub adopters aren't misled.

## Rationale
Two small fixes surfaced during the v3.0 feedback evaluation but didn't fit the schema-redesign feature set (fs-010). Both reduce false confidence in what the board displays:

- A claim sitting with no commits in 18h looks alive until someone reads the file.
- Polling tries to hit GitHub even on `file://` and non-GitHub hosts, then quietly fails.

Bundled because they're the same shape of fix at different layers (render + config). Independent on their own; together they're a coherent "honest presentation" pass.

## Tickets
- HB-077 — Stale-claim render on in-progress cards
- HB-078 — Polling source honesty + README update

## Status
Backlog
