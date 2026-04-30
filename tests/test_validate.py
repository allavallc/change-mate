"""Tests for horde-of-bots/validate.py — one fixture per error class."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "horde-of-bots"))
from validate import validate


REPO_ROOT = Path(__file__).parent.parent

FOLDERS = ("backlog", "in-progress", "done", "blocked", "not-doing", "feature-sets")


def make_repo(tmp_path, prefix="HB"):
    """Build a minimal horde-of-bots/ tree under tmp_path."""
    base = tmp_path / "horde-of-bots"
    base.mkdir()
    for f in FOLDERS:
        (base / f).mkdir()
    (base / "config.json").write_text(
        f'{{"project_name": "Test", "ticket_prefix": "{prefix}"}}',
        encoding="utf-8",
    )
    return base


def write_ticket(base, folder, tid, body):
    p = base / folder / f"{tid}-1.md"
    p.write_text(body, encoding="utf-8")
    return p


VALID_BACKLOG = """# [HB-001] Backlog item

- **Status**: open
- **Priority**: Medium
- **Effort**: S
- **Assigned to**:

## Goal
g
"""


VALID_DONE = """# [HB-002] Done item

- **Status**: done
- **Priority**: Medium
- **Effort**: S
- **Assigned to**: claude
- **Completed**: 2026-04-30
- **Verification**: bot-claimed

## Goal
g
"""


VALID_BLOCKED = """# [HB-003] Blocked item

- **Status**: blocked
- **Priority**: Medium
- **Effort**: S
- **Failure mode**: needs-human

## Goal
g
"""


def test_clean_tree_passes(tmp_path):
    base = make_repo(tmp_path)
    write_ticket(base, "backlog", "HB-001", VALID_BACKLOG)
    write_ticket(base, "done", "HB-002", VALID_DONE)
    write_ticket(base, "blocked", "HB-003", VALID_BLOCKED)
    errors, count = validate(tmp_path)
    assert errors == []
    assert count == 3


def test_missing_priority(tmp_path):
    base = make_repo(tmp_path)
    body = """# [HB-001] No priority

- **Status**: open
- **Effort**: S

## Goal
g
"""
    write_ticket(base, "backlog", "HB-001", body)
    errors, _ = validate(tmp_path)
    assert any("Priority" in e for e in errors)


def test_missing_effort(tmp_path):
    base = make_repo(tmp_path)
    body = """# [HB-001] No effort

- **Status**: open
- **Priority**: Medium

## Goal
g
"""
    write_ticket(base, "backlog", "HB-001", body)
    errors, _ = validate(tmp_path)
    assert any("Effort" in e for e in errors)


def test_status_folder_mismatch(tmp_path):
    base = make_repo(tmp_path)
    body = """# [HB-001] Wrong status

- **Status**: done
- **Priority**: Medium
- **Effort**: S

## Goal
g
"""
    write_ticket(base, "backlog", "HB-001", body)
    errors, _ = validate(tmp_path)
    assert any("Status='done'" in e and "backlog/" in e for e in errors)


def test_unparseable_started_date(tmp_path):
    base = make_repo(tmp_path)
    body = """# [HB-001] Bad date

- **Status**: in-progress
- **Priority**: Medium
- **Effort**: S
- **Assigned to**: claude
- **Started**: yesterday afternoon

## Goal
g
"""
    write_ticket(base, "in-progress", "HB-001", body)
    errors, _ = validate(tmp_path)
    assert any("not a parseable date" in e for e in errors)


def test_done_without_completed(tmp_path):
    base = make_repo(tmp_path)
    body = """# [HB-001] Done but no completed date

- **Status**: done
- **Priority**: Medium
- **Effort**: S
- **Assigned to**: claude
- **Verification**: bot-claimed

## Goal
g
"""
    write_ticket(base, "done", "HB-001", body)
    errors, _ = validate(tmp_path)
    assert any("Completed" in e and "required" in e for e in errors)


def test_done_without_verification(tmp_path):
    base = make_repo(tmp_path)
    body = """# [HB-001] Done without verification

- **Status**: done
- **Priority**: Medium
- **Effort**: S
- **Assigned to**: claude
- **Completed**: 2026-04-30

## Goal
g
"""
    write_ticket(base, "done", "HB-001", body)
    errors, _ = validate(tmp_path)
    assert any("Verification" in e and "required" in e for e in errors)


def test_done_invalid_verification(tmp_path):
    base = make_repo(tmp_path)
    body = """# [HB-001] Bad verification value

- **Status**: done
- **Priority**: Medium
- **Effort**: S
- **Assigned to**: claude
- **Completed**: 2026-04-30
- **Verification**: gold-stamped

## Goal
g
"""
    write_ticket(base, "done", "HB-001", body)
    errors, _ = validate(tmp_path)
    assert any("not in allowed set" in e and "gold-stamped" in e for e in errors)


def test_blocked_without_failure_mode(tmp_path):
    base = make_repo(tmp_path)
    body = """# [HB-001] Blocked without mode

- **Status**: blocked
- **Priority**: Medium
- **Effort**: S

## Goal
g
"""
    write_ticket(base, "blocked", "HB-001", body)
    errors, _ = validate(tmp_path)
    assert any("Failure mode" in e and "required" in e for e in errors)


def test_blocked_invalid_failure_mode(tmp_path):
    base = make_repo(tmp_path)
    body = """# [HB-001] Blocked bad mode

- **Status**: blocked
- **Priority**: Medium
- **Effort**: S
- **Failure mode**: vibes-off

## Goal
g
"""
    write_ticket(base, "blocked", "HB-001", body)
    errors, _ = validate(tmp_path)
    assert any("not in allowed set" in e and "vibes-off" in e for e in errors)


def test_in_progress_without_assigned_to(tmp_path):
    base = make_repo(tmp_path)
    body = """# [HB-001] Working but unassigned

- **Status**: in-progress
- **Priority**: Medium
- **Effort**: S

## Goal
g
"""
    write_ticket(base, "in-progress", "HB-001", body)
    errors, _ = validate(tmp_path)
    assert any("Assigned to" in e and "required" in e for e in errors)


def test_unresolved_blocked_by_reference(tmp_path):
    base = make_repo(tmp_path)
    body = """# [HB-001] References ghost

- **Status**: open
- **Priority**: Medium
- **Effort**: S
- **Blocked by**: HB-9999

## Goal
g
"""
    write_ticket(base, "backlog", "HB-001", body)
    errors, _ = validate(tmp_path)
    assert any("HB-9999" in e and "no such ticket" in e for e in errors)


def test_unresolved_split_from_reference(tmp_path):
    base = make_repo(tmp_path)
    body = """# [HB-001] References ghost parent

- **Status**: open
- **Priority**: Medium
- **Effort**: S
- **Split from**: HB-9999

## Goal
g
"""
    write_ticket(base, "backlog", "HB-001", body)
    errors, _ = validate(tmp_path)
    assert any("HB-9999" in e and "no such ticket" in e for e in errors)


def test_done_with_unmet_dep(tmp_path):
    base = make_repo(tmp_path)
    write_ticket(base, "backlog", "HB-001", VALID_BACKLOG)
    body = """# [HB-002] Done while dep is in backlog

- **Status**: done
- **Priority**: Medium
- **Effort**: S
- **Assigned to**: claude
- **Completed**: 2026-04-30
- **Verification**: bot-claimed
- **Blocked by**: HB-001

## Goal
g
"""
    write_ticket(base, "done", "HB-002", body)
    errors, _ = validate(tmp_path)
    assert any(
        "cannot be in 'done/'" in e and "HB-001" in e and "backlog/" in e
        for e in errors
    )


def test_no_horde_of_bots_dir_returns_empty(tmp_path):
    """If horde-of-bots/ doesn't exist, validator no-ops cleanly."""
    errors, count = validate(tmp_path)
    assert errors == []
    assert count == 0
