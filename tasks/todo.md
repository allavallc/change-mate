# CM-003 — Plan

Add `Related`, `Blocks`, `Blocked by` fields to tickets; render as chips on the board with auto-inferred inverse edges; warn on orphans and cycles.

## Design agreed with user

- **Symmetry**: inferred at render time. One side of the edge is written (`Blocks: CM-006` on CM-005's file); the renderer walks the reverse map and shows `Blocked by: CM-005` on CM-006's card automatically. Source stays clean.
- **Placement**: all chips on card face, cap at 3 visible, "+N more" overflow if more.
- **Orphan / cycle**: warn in build log, skip the broken chip, keep building. Non-fatal.

## Phased build

Three phases, each with its own commit + approval gate. Max 5 files per phase.

### Phase 1 — Parser + format docs + tests
- [ ] `build_lib.py`: extract `related`, `blocks`, `blocked_by` bullet fields on `parse_ticket`. Store as list of CM-IDs (comma-split, whitespace-stripped, deduped).
- [ ] `CHANGEMATE.md`: add the three fields to the ticket file format block; document that `Blocked by` is required when a ticket lives in `blocked/`; add a brief note on how inverse edges are rendered (not persisted).
- [ ] `tests/test_parser.py`: add tests for each field — present / missing / single / multiple IDs / malformed / empty-value.
- **Files**: `build_lib.py`, `CHANGEMATE.md`, `tests/test_parser.py` (3 files)
- **Verify**: all 24+ existing tests green; new tests cover the new fields.

### Phase 2 — Board rendering + symmetry inference + orphan/cycle warnings
- [ ] `build.sh` Python portion: pre-render pass walks every ticket, builds reverse-edge map, detects orphans (CM-ID referenced but file missing) and cycles. Emits warnings to stderr.
- [ ] `build.sh` JS portion: render Related / Blocks / Blocked by chips on card face. Cap at 3 visible, "+N more" overflow pill. Inverse edges (computed in Python) injected into each ticket's JSON under `blocked_by_inferred`.
- [ ] `build.sh` CSS: `.card-rel` chip style (neutral, smaller than priority badge). Distinguish the three kinds by a small prefix glyph or label.
- [ ] De-dupe rule: if CM-B's file explicitly lists `Blocked by: CM-A` AND CM-A's file lists `Blocks: CM-B`, render only once.
- **Files**: `build.sh` (1 file)
- **Verify**: `bash -n` clean. Build against current backlog: warnings for any orphans (expected: zero today). Visual inspection of rendered card on a ticket we add with relationships.

### Phase 3 — PM skill + workflow docs
- [ ] `skills/product-manager/SKILL.md`: add a section "Relationships" describing when and how to set Related / Blocks / Blocked by during drafting. Principles: only one side of the edge should be written; prefer the side that best describes the intent (use `Blocks` on the upstream ticket, not `Blocked by` on both).
- [ ] `CHANGEMATE.md`: add a brief "Blocking a ticket" section documenting the `Blocked by` requirement when moving to `blocked/`.
- [ ] `tests/test_parser.py`: add a test for a full ticket with all three fields populated + orphan detection test (build-level, can live in a new `tests/test_build_relationships.py` if cleaner).
- **Files**: `skills/product-manager/SKILL.md`, `CHANGEMATE.md`, `tests/test_parser.py` or new test file (3 files max)
- **Verify**: tests green. Read CHANGEMATE.md + SKILL.md top-to-bottom as a fresh agent — the relationship model is clear.

## Success signals (for the whole ticket)
- A new ticket can express a dependency using any of the three fields
- Inverse edges appear automatically on the counterpart card
- Orphans and cycles produce build-time warnings without breaking the build
- Tests cover parsing and build-time detection
- PM skill and CHANGEMATE.md together give agents unambiguous guidance

## Failure signals / what to watch
- Symmetric inference rendering the same edge twice (one from explicit, one from inferred)
- Chip cap producing a misleading "+2 more" when one of the two is already visible
- Orphan warning spam in CI if a ticket gets deleted but still referenced elsewhere
- PM skill drifting into writing both sides of every edge (violates the one-write rule)

## Not in scope
- Clickable chips that scroll/highlight the target — polish, save for a follow-up if desired
- Visual graph view of relationships — out of scope, would be its own ticket
- Dependency enforcement at workflow time (e.g. refusing to mark CM-B done while CM-A still blocks something) — out of scope
