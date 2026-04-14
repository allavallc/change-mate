from pathlib import Path

import pytest

from build_lib import parse_ticket, parse_feature_set


def write(tmp_path, name, body):
    p = tmp_path / name
    p.write_text(body, encoding="utf-8")
    return p


# ---------- parse_ticket ----------


def test_parse_legacy_ticket(tmp_path):
    body = """# [CM-001] Legacy ticket

- **Status**: done
- **Priority**: Low
- **Effort**: XS
- **Assigned to**: alice
- **Started**: 2026-04-13 00:00
- **Completed**: 2026-04-14

## Goal
Old-style goal.

## Why
Old-style why.

## Done when
- thing one
- thing two

## Notes
Old notes.
"""
    p = write(tmp_path, "CM-001-1736000000.md", body)
    t = parse_ticket(p, "done")

    assert t["id"] == "CM-001"
    assert t["title"] == "Legacy ticket"
    assert t["status"] == "done"
    assert t["priority"] == "Low"
    assert t["effort"] == "XS"
    assert t["assigned_to"] == "alice"
    assert t["goal"] == "Old-style goal."
    assert t["why"] == "Old-style why."
    assert t["done_when"] == ["thing one", "thing two"]
    assert t["notes"] == "Old notes."

    # New fields default to empty for legacy tickets
    assert t["feature_set"] == ""
    assert t["desired_output"] == ""
    assert t["success_signals"] == ""
    assert t["failure_signals"] == ""
    assert t["tests"] == ""


def test_parse_new_ticket_full(tmp_path):
    body = """# [CM-042] Full new format

- **Status**: open
- **Priority**: High
- **Effort**: M
- **Feature set**: feature-set-001-workflow
- **Assigned to**: claude

## Goal
One-sentence problem statement.

## Why
The value of solving it.

## Done when
- criterion one
- criterion two

## Desired output
The observable result.

## Success signals
- signal one
- signal two

## Failure signals
- watch for X
- watch for Y

## Tests
- test_case_one
- test_case_two

## Notes
Decisions, alternatives, out-of-scope.
"""
    p = write(tmp_path, "CM-042-1776000000.md", body)
    t = parse_ticket(p, "backlog")

    assert t["id"] == "CM-042"
    assert t["title"] == "Full new format"
    assert t["feature_set"] == "feature-set-001-workflow"
    assert t["goal"] == "One-sentence problem statement."
    assert t["done_when"] == ["criterion one", "criterion two"]
    assert t["desired_output"] == "The observable result."
    assert "signal one" in t["success_signals"]
    assert "signal two" in t["success_signals"]
    assert "watch for X" in t["failure_signals"]
    assert "test_case_one" in t["tests"]
    assert t["notes"].startswith("Decisions")


def test_parse_partial_new_ticket(tmp_path):
    body = """# [CM-100] Partial new

- **Status**: open
- **Feature set**: feature-set-002-partial

## Goal
Has goal and feature set, but most new sections missing.

## Desired output
Only this new section is filled.
"""
    p = write(tmp_path, "CM-100-1776000001.md", body)
    t = parse_ticket(p, "backlog")

    assert t["feature_set"] == "feature-set-002-partial"
    assert t["desired_output"] == "Only this new section is filled."
    # Other new sections should be empty
    assert t["success_signals"] == ""
    assert t["failure_signals"] == ""
    assert t["tests"] == ""
    # Legacy sections also empty when missing
    assert t["why"] == ""
    assert t["done_when"] == []


def test_parse_ticket_id_from_filename_when_header_missing(tmp_path):
    body = """no header here

- **Status**: open
"""
    p = write(tmp_path, "CM-077-1776000002.md", body)
    t = parse_ticket(p, "backlog")
    assert t["id"] == "CM-077"
    assert t["title"] == ""


def test_parse_ticket_default_status_used_when_missing(tmp_path):
    body = """# [CM-200] No status bullet

## Goal
g
"""
    p = write(tmp_path, "CM-200.md", body)
    t = parse_ticket(p, "blocked")
    assert t["status"] == "blocked"


# ---------- parse_feature_set ----------


def test_parse_feature_set_new_format(tmp_path):
    body = """# [feature-set-001] Workflow Hygiene

## Goal
Polish the change-mate workflow surface.

## Rationale
CM-003 and CM-004 belong together because both reshape ticket structure.

## Tickets
- CM-003 — Ticket relationships
- CM-004 — Reframe persona

## Status
In progress
"""
    p = write(tmp_path, "feature-set-001-workflow.md", body)
    s = parse_feature_set(p)

    assert "Workflow Hygiene" in s["name"]
    assert s["goal"] == "Polish the change-mate workflow surface."
    assert "ticket structure" in s["rationale"]
    assert s["status"] == "In progress"
    assert s["tickets"] == ["CM-003", "CM-004"]


def test_parse_feature_set_legacy_bullet_format(tmp_path):
    body = """# Legacy feature set

- **Goal**: legacy goal text
- **Status**: planned
- **Tickets**: CM-005, CM-006, CM-007
"""
    p = write(tmp_path, "feature-set-legacy.md", body)
    s = parse_feature_set(p)

    assert s["goal"] == "legacy goal text"
    assert s["status"] == "planned"
    assert s["tickets"] == ["CM-005", "CM-006", "CM-007"]


def test_parse_feature_set_new_overrides_legacy(tmp_path):
    body = """# Mixed

- **Goal**: bullet goal
- **Status**: planned

## Goal
section goal wins

## Status
Complete
"""
    p = write(tmp_path, "feature-set-mixed.md", body)
    s = parse_feature_set(p)
    assert s["goal"] == "section goal wins"
    assert s["status"] == "Complete"


# ---------- relationship fields ----------


def test_parse_relationships_all_three_fields(tmp_path):
    body = """# [CM-500] Relationships

- **Status**: open
- **Related**: CM-001, CM-002
- **Blocks**: CM-003
- **Blocked by**: CM-004, CM-005, CM-006

## Goal
g
"""
    p = write(tmp_path, "CM-500.md", body)
    t = parse_ticket(p, "backlog")
    assert t["related"] == ["CM-001", "CM-002"]
    assert t["blocks"] == ["CM-003"]
    assert t["blocked_by"] == ["CM-004", "CM-005", "CM-006"]


def test_parse_relationships_missing_fields_default_to_empty_list(tmp_path):
    body = """# [CM-501] No relationships

- **Status**: open

## Goal
g
"""
    p = write(tmp_path, "CM-501.md", body)
    t = parse_ticket(p, "backlog")
    assert t["related"] == []
    assert t["blocks"] == []
    assert t["blocked_by"] == []


def test_parse_relationships_empty_value_is_empty_list(tmp_path):
    body = """# [CM-502] Empty values

- **Status**: open
- **Related**:
- **Blocks**:
- **Blocked by**:

## Goal
g
"""
    p = write(tmp_path, "CM-502.md", body)
    t = parse_ticket(p, "backlog")
    assert t["related"] == []
    assert t["blocks"] == []
    assert t["blocked_by"] == []


def test_parse_relationships_single_id_no_comma(tmp_path):
    body = """# [CM-503] Single

- **Status**: open
- **Related**: CM-007

## Goal
g
"""
    p = write(tmp_path, "CM-503.md", body)
    t = parse_ticket(p, "backlog")
    assert t["related"] == ["CM-007"]


def test_parse_relationships_whitespace_tolerant(tmp_path):
    body = """# [CM-504] Whitespace

- **Status**: open
- **Related**:   CM-001 ,  CM-002   ,CM-003
- **Blocks**: CM-004,CM-005

## Goal
g
"""
    p = write(tmp_path, "CM-504.md", body)
    t = parse_ticket(p, "backlog")
    assert t["related"] == ["CM-001", "CM-002", "CM-003"]
    assert t["blocks"] == ["CM-004", "CM-005"]


def test_parse_relationships_malformed_entries_dropped(tmp_path):
    body = """# [CM-505] Malformed

- **Status**: open
- **Related**: CM-001, foo, CM-ABC, , CM-002, bar

## Goal
g
"""
    p = write(tmp_path, "CM-505.md", body)
    t = parse_ticket(p, "backlog")
    assert t["related"] == ["CM-001", "CM-002"]


def test_parse_relationships_deduped(tmp_path):
    body = """# [CM-506] Dupes

- **Status**: open
- **Blocked by**: CM-010, CM-011, CM-010, CM-011

## Goal
g
"""
    p = write(tmp_path, "CM-506.md", body)
    t = parse_ticket(p, "backlog")
    assert t["blocked_by"] == ["CM-010", "CM-011"]


# ---------- regression: every committed ticket parses ----------


def test_every_committed_ticket_parses_without_error():
    repo_root = Path(__file__).parent.parent
    base = repo_root / "change-mate"
    if not base.exists():
        pytest.skip("change-mate directory not present")
    for folder in ("backlog", "in-progress", "done", "blocked", "not-doing"):
        d = base / folder
        if not d.exists():
            continue
        for f in sorted(d.glob("CM-*.md")):
            t = parse_ticket(f, folder)
            assert t["id"], f"empty id for {f.name}"
            assert t["status"], f"empty status for {f.name}"
