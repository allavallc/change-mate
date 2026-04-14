# CM-004 — Plan

Reframe agent persona to senior technical PM, introduce LLM-driven ticket intake via a reusable "product-manager" skill, expand the ticket format with PM-grade sections, auto-assign feature sets, and stand up a proper test harness.

## Scope summary

1. **Persona sweep of `CHANGEMATE.md`** — remove all dev-voice language; replace with senior technical PM voice. The agent's job at this layer is shaping features inside feature sets, not writing code.
2. **New reusable skill: `product-manager`** — the core behavior. Ships in the repo, installed by `setup.sh` into `~/.claude/skills/product-manager/SKILL.md`. Defines: how a PM gathers info, drafts tickets, detects feature-set membership, proposes new feature sets, flags risks and alternatives.
3. **Ticket format extended** with four new sections: `## Desired output`, `## Success signals`, `## Failure signals`, `## Tests`.
4. **Intake flow inverted** — LLM drafts first, asks only when genuinely ambiguous. Old 6-question numbered list retired.
5. **Feature set auto-assignment** — on every new ticket, PM skill inspects existing feature sets, proposes membership or creates a new `feature-set-XXX.md`.
6. **Board rendering**:
   - Feature set name always shown on card face (with link to feature set detail)
   - New sections (`Desired output`, `Success`, `Failure`, `Tests`) only visible when card is opened
7. **Parser + build** — `build_lib.py` reads new sections; `build.sh` renders them on card open; backward-compatible with legacy tickets (CM-001, CM-002).
8. **Test harness** — stand up `pytest`, create `tests/` folder, add GitHub Actions workflow that runs on every PR.
9. **Backfill** — rewrite CM-003 and CM-005–CM-009 into the new structured format once it's live.

## Open scope boundary

- Relationship chips on the card face (blocks / blocked-by / related-to) belong to **CM-003**, not this ticket. This ticket leaves chip rendering for CM-003.
- Second-LLM review of drafts → **CM-010** (now in backlog, low priority, after CM-004).

## Phased build

Each phase commits independently, passes tests, and is approved before the next begins. Max 5 files per phase.

### Phase 1 — `CHANGEMATE.md` persona sweep (docs only)
- [ ] Rewrite the opening persona paragraph to senior technical PM voice
- [ ] Remove/rewrite every "developer" reference in favor of PM framing
- [ ] Retire the 6-question numbered intake; replace with "PM skill drafts first, asks only when ambiguous"
- [ ] Document the new ticket format (4 new sections)
- [ ] Document the feature-set auto-assignment expectation
- [ ] Document the `product-manager` skill as the required intake tool
- **Files**: `CHANGEMATE.md` (1 file)
- **Verify**: read top-to-bottom as a new agent — is the PM framing coherent end-to-end? No dev-voice leaks.

### Phase 2 — Product-manager skill
- [ ] Create `skills/product-manager/SKILL.md` in the change-mate repo
- [ ] Define behaviors: gather-before-draft, draft-all-sections, auto-feature-set, propose-alternatives, flag-risks
- [ ] Define trigger conditions and example invocations
- [ ] Update `setup.sh` to copy the skill into `~/.claude/skills/product-manager/` on install
- [ ] Document the skill in `CHANGEMATE.md` (link, purpose, when to use)
- **Files**: `skills/product-manager/SKILL.md`, `setup.sh`, `CHANGEMATE.md` (3 files)
- **Verify**: fresh install of change-mate → skill appears in the user's skill list and is invokable.

### Phase 3 — Ticket format + parser
- [ ] Update `CHANGEMATE.md` ticket format block with the four new sections
- [ ] Update `build_lib.py` `parse_ticket` to extract each new section (present → string; missing → None)
- [ ] Add `feature_set` field on the parsed ticket (read from a `**Feature set**: feature-set-XXX` header line)
- [ ] Ensure legacy tickets (no new sections) still parse and produce valid board entries
- **Files**: `CHANGEMATE.md`, `build_lib.py` (2 files)
- **Verify**: run parser against every existing ticket in `change-mate/` → zero errors.

### Phase 4 — Board rendering
- [ ] Update `build.sh` to render `feature_set` on card face (always visible when present)
- [ ] Update `build.sh` card-open modal to display the four new sections when present
- [ ] Gracefully hide any new section that's absent (no empty headers)
- **Files**: `build.sh`, `change-mate-board.html` template portion inside `build.sh` (1 file — board HTML regenerates automatically via Actions)
- **Verify**: open live board → new-format tickets show feature set on face, full detail on open; legacy tickets look unchanged.

### Phase 5 — Test harness
- [ ] Create `tests/` folder with `tests/test_parser.py`
- [ ] Unit tests for `parse_ticket`: legacy format, full new format, partial new format, malformed sections, feature-set line present/absent
- [ ] Add `requirements-dev.txt` (pytest) or `pyproject.toml` test config
- [ ] Add `.github/workflows/test.yml` — runs `pytest` on every PR and push to `main`
- [ ] Update `CLAUDE.md` (project-level) to note the test command
- **Files**: `tests/test_parser.py`, `requirements-dev.txt`, `.github/workflows/test.yml`, `CLAUDE.md` (4 files)
- **Verify**: push → Actions runs pytest → green.

### Phase 6 — Backfill existing tickets
- [ ] Rewrite CM-003, CM-005, CM-006, CM-007, CM-008, CM-009 into the new structured sections (content already exists in prose — just restructure)
- [ ] Add `**Feature set**: feature-set-001-supabase-upgrade` (or whatever the PM skill proposes) to CM-005/006/007/008/009
- [ ] Add `**Feature set**: feature-set-002-workflow-hygiene` to CM-003 and CM-004 itself
- [ ] Create `feature-sets/feature-set-001.md` and `feature-sets/feature-set-002.md` if not already present
- **Files**: 6 ticket files + 2 feature set files (8 files — split into two phases of 4 if needed)
- **Verify**: board rebuild shows all tickets with feature-set labels, all new sections render correctly.

## Success signals (for the whole ticket)
- New tickets created after ship contain all four new sections — LLM drafts them without prompting
- Tickets are automatically grouped under feature sets on the board
- Parser and renderer handle legacy + new formats with zero errors
- pytest runs green in CI
- Dev working from a new-format ticket has enough context to build without follow-up questions

## Failure signals / what to watch
- Parser crashing on malformed sections from older or hand-written tickets
- LLM drifting back into dev-voice on sub-tasks (skill prompt needs to be firm and repeated)
- Feature-set proposals feeling random — skill needs clear heuristics for "is this a match"
- Board card face getting visually crowded by the feature-set label
- Tests flaking on CRLF/LF line ending differences (Windows ↔ CI)

## Tests required
- `test_parse_legacy_ticket` — old format parses cleanly, new fields are None
- `test_parse_new_ticket` — all four new sections + feature_set populate
- `test_parse_partial_new_ticket` — some new sections missing, others present
- `test_parse_feature_set_line` — feature_set header parsed from markdown bullet
- `test_board_render_card_face_legacy` — no feature set, no new sections → original card
- `test_board_render_card_face_new` — feature set shown on face, new sections in detail view

## Rollout / order-of-operations
Phase 1 → 2 → 3 → 4 → 5 → 6. Each phase is a separate commit, separate PR review, and explicit "go Phase N+1" from the user. No phase may touch more than 5 files.

## Not in scope (explicit)
- Relationship fields + chip rendering → CM-003
- Second-LLM review → CM-010
- Supabase / Edge Function work → CM-005–CM-009
