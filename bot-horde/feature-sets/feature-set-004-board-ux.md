# [feature-set-004] Board UX

## Goal
Make the board feel alive to humans watching, while keeping the presentation calm and the implementation dependency-free.

## Rationale
The board is the primary "humans watch what bots are doing" surface. Static cards do not communicate that work is actually happening; subtle animation does. This feature set collects polish work that improves the watching experience without adding runtime dependencies or heavy assets.

## Tickets
- BH-052 — Walking-robot perimeter animation on in-progress cards
- BH-053 — Animation demo, agent #1 (do not move)
- BH-054 — Animation demo, agent #2 (do not move)
- BH-055 — Animation demo, agent #3 (do not move)
- BH-056 — Animation demo, agent #4 (do not move)

## Status
Done — 2026-04-27

## Outcome
Robot animation shipped (BH-052). User approved the direction 2026-04-27 — per-agent SVG robot walks the card perimeter clockwise on a 12s loop, color hashed from `assigned_to`, random `animation-delay` per page load so multiple cards stagger naturally. Demo placeholders BH-053-056 served their visual-evaluation purpose and moved to `not-doing/`.
