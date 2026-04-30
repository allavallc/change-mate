import shutil
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "horde-of-bots"))
from build_lib import parse_feature_set, parse_ticket

REPO_ROOT = Path(__file__).parent.parent

# ---------------------------------------------------------------------------
# Fixture content
# ---------------------------------------------------------------------------

FULL_TICKET = """\
# [CM-001] Add login page

- **Status**: open
- **Priority**: High
- **Effort**: M
- **Assigned to**: Alex
- **Started**:
- **Completed**:

## Goal
Add email/password login.

## Why
Users cannot save anything without an account.

## Done when
- User can register
- User can log in and out

## Notes
Use JWT, not sessions.
"""

REJECTED_TICKET = """\
# [CM-005] Dark mode toggle

- **Status**: not-doing
- **Priority**: Low
- **Effort**: S
- **Assigned to**:
- **Started**:
- **Completed**:
- **Rejected by**: Alex
- **Rejected**: 2026-04-09
- **Rejection reason**: Out of scope for current milestone

## Goal
Add a dark/light mode toggle to the header.

## Why
Nice to have.

## Done when
- Toggle visible in header
- Preference persists across sessions

## Notes
"""

REJECTED_NA_TICKET = """\
# [CM-006] Rebrand colors

- **Status**: not-doing
- **Rejected by**: user
- **Rejected**: 2026-04-09
- **Rejection reason**: n/a

## Goal
Update brand colors across the app.

## Why
Marketing requested it.

## Done when

## Notes
"""

FEATURE_SET = """\
# Feature Set 1 — Core Auth

- **Status**: active
- **Goal**: Ship login, registration, and password reset
- **Tickets**: CM-001, CM-002, CM-005
"""


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def write(tmp_path, rel, content):
    f = tmp_path / rel
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(content, encoding="utf-8")
    return f


# ---------------------------------------------------------------------------
# parse_ticket — basic parsing
# ---------------------------------------------------------------------------

def test_id_and_title_from_header(tmp_path):
    f = write(tmp_path, "CM-001-1000.md", FULL_TICKET)
    t = parse_ticket(f, "open")
    assert t["id"] == "CM-001"
    assert t["title"] == "Add login page"


def test_id_extracted_from_filename_when_header_missing(tmp_path):
    content = "no header line\n\n## Goal\nSomething.\n"
    f = write(tmp_path, "CM-042-9999.md", content)
    t = parse_ticket(f, "open")
    assert t["id"] == "CM-042"


def test_standard_fields_parsed(tmp_path):
    f = write(tmp_path, "CM-001-1000.md", FULL_TICKET)
    t = parse_ticket(f, "open")
    assert t["priority"] == "High"
    assert t["effort"] == "M"
    assert t["assigned_to"] == "Alex"


def test_sections_parsed(tmp_path):
    f = write(tmp_path, "CM-001-1000.md", FULL_TICKET)
    t = parse_ticket(f, "open")
    assert t["goal"] == "Add email/password login."
    assert t["why"] == "Users cannot save anything without an account."
    assert t["done_when"] == ["User can register", "User can log in and out"]
    assert t["notes"] == "Use JWT, not sessions."


def test_status_in_file_overrides_folder_default(tmp_path):
    f = write(tmp_path, "CM-001-1000.md", FULL_TICKET)
    t = parse_ticket(f, "blocked")   # folder says blocked
    assert t["status"] == "open"     # file says open — file wins


def test_default_status_used_when_not_in_file(tmp_path):
    content = "# [CM-010] No status\n\n## Goal\nSomething.\n"
    f = write(tmp_path, "CM-010-1000.md", content)
    t = parse_ticket(f, "in-progress")
    assert t["status"] == "in-progress"


# ---------------------------------------------------------------------------
# parse_ticket — rejection fields
# ---------------------------------------------------------------------------

def test_rejection_fields_parsed(tmp_path):
    f = write(tmp_path, "CM-005-1000.md", REJECTED_TICKET)
    t = parse_ticket(f, "not-doing")
    assert t["status"] == "not-doing"
    assert t["rejected_by"] == "Alex"
    assert t["rejected"] == "2026-04-09"
    assert t["rejection_reason"] == "Out of scope for current milestone"


def test_rejection_reason_na(tmp_path):
    f = write(tmp_path, "CM-006-1000.md", REJECTED_NA_TICKET)
    t = parse_ticket(f, "not-doing")
    assert t["rejection_reason"] == "n/a"


def test_rejection_fields_blank_for_normal_ticket(tmp_path):
    f = write(tmp_path, "CM-001-1000.md", FULL_TICKET)
    t = parse_ticket(f, "open")
    assert t["rejected_by"] == ""
    assert t["rejected"] == ""
    assert t["rejection_reason"] == ""


# ---------------------------------------------------------------------------
# parse_feature_set
# ---------------------------------------------------------------------------

def test_feature_set_name(tmp_path):
    f = write(tmp_path, "feature-set-001.md", FEATURE_SET)
    s = parse_feature_set(f)
    assert s["name"] == "Feature Set 1 — Core Auth"


def test_feature_set_fields(tmp_path):
    f = write(tmp_path, "feature-set-001.md", FEATURE_SET)
    s = parse_feature_set(f)
    assert s["status"] == "active"
    assert s["goal"] == "Ship login, registration, and password reset"
    assert s["tickets"] == ["CM-001", "CM-002", "CM-005"]


def test_feature_set_default_status(tmp_path):
    f = write(tmp_path, "feature-set-002.md", "# Feature Set 2\n\n- **Goal**: Something\n")
    s = parse_feature_set(f)
    assert s["status"] == "planned"


def test_feature_set_empty_tickets(tmp_path):
    f = write(tmp_path, "feature-set-003.md", "# Feature Set 3\n\n- **Status**: planned\n")
    s = parse_feature_set(f)
    assert s["tickets"] == []


# ---------------------------------------------------------------------------
# Integration: build.sh against fixture tickets
# ---------------------------------------------------------------------------

def test_build_generates_html(tmp_path):
    for folder in ("backlog", "in-progress", "done", "blocked", "not-doing", "feature-sets"):
        (tmp_path / "horde-of-bots" / folder).mkdir(parents=True)

    write(tmp_path, "horde-of-bots/backlog/CM-001-1000.md", FULL_TICKET)
    write(tmp_path, "horde-of-bots/not-doing/CM-005-1001.md", REJECTED_TICKET)
    write(tmp_path, "horde-of-bots/feature-sets/feature-set-001.md", FEATURE_SET)

    shutil.copy(REPO_ROOT / "horde-of-bots" / "build.sh", tmp_path / "horde-of-bots" / "build.sh")
    shutil.copy(REPO_ROOT / "horde-of-bots" / "build_lib.py", tmp_path / "horde-of-bots" / "build_lib.py")
    shutil.copy(REPO_ROOT / "horde-of-bots" / "validate.py", tmp_path / "horde-of-bots" / "validate.py")

    result = subprocess.run(
        ["bash", "horde-of-bots/build.sh"],
        cwd=tmp_path,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    assert "horde-of-bots/board.html updated" in result.stdout

    html = (tmp_path / "horde-of-bots" / "board.html").read_text(encoding="utf-8")

    # Board structure
    assert "btn-rejected" in html
    assert "col-rejected" in html
    assert "toggleRejected" in html

    # Active ticket
    assert "CM-001" in html
    assert "Add login page" in html

    # Rejected ticket and its reason
    assert "CM-005" in html
    assert "Dark mode toggle" in html
    assert "Out of scope for current milestone" in html

    # Feature set
    assert "Feature Set 1" in html
    assert "Ship login, registration, and password reset" in html


def test_build_with_pollsource_none_renders_static_indicator(tmp_path):
    """HB-078: pollSource=none changes JS branch and indicator copy."""
    for folder in ("backlog", "in-progress", "done", "blocked", "not-doing", "feature-sets"):
        (tmp_path / "horde-of-bots" / folder).mkdir(parents=True)

    write(tmp_path, "horde-of-bots/backlog/CM-001-1000.md", FULL_TICKET)
    write(
        tmp_path,
        "horde-of-bots/config.json",
        '{"project_name": "Test", "ticket_prefix": "CM", "pollSource": "none"}',
    )

    shutil.copy(REPO_ROOT / "horde-of-bots" / "build.sh", tmp_path / "horde-of-bots" / "build.sh")
    shutil.copy(REPO_ROOT / "horde-of-bots" / "build_lib.py", tmp_path / "horde-of-bots" / "build_lib.py")
    shutil.copy(REPO_ROOT / "horde-of-bots" / "validate.py", tmp_path / "horde-of-bots" / "validate.py")

    result = subprocess.run(["bash", "horde-of-bots/build.sh"], cwd=tmp_path, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr

    html = (tmp_path / "horde-of-bots" / "board.html").read_text(encoding="utf-8")
    assert '"poll_source": "none"' in html
    assert "refresh manually" in html


def test_build_invalid_pollsource_falls_back_with_warning(tmp_path):
    """HB-078: unknown pollSource warns and falls back to 'github'."""
    for folder in ("backlog", "in-progress", "done", "blocked", "not-doing", "feature-sets"):
        (tmp_path / "horde-of-bots" / folder).mkdir(parents=True)

    write(tmp_path, "horde-of-bots/backlog/CM-001-1000.md", FULL_TICKET)
    write(
        tmp_path,
        "horde-of-bots/config.json",
        '{"project_name": "Test", "ticket_prefix": "CM", "pollSource": "gitlab"}',
    )

    shutil.copy(REPO_ROOT / "horde-of-bots" / "build.sh", tmp_path / "horde-of-bots" / "build.sh")
    shutil.copy(REPO_ROOT / "horde-of-bots" / "build_lib.py", tmp_path / "horde-of-bots" / "build_lib.py")
    shutil.copy(REPO_ROOT / "horde-of-bots" / "validate.py", tmp_path / "horde-of-bots" / "validate.py")

    result = subprocess.run(["bash", "horde-of-bots/build.sh"], cwd=tmp_path, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert "pollSource='gitlab' is not recognized" in result.stderr

    html = (tmp_path / "horde-of-bots" / "board.html").read_text(encoding="utf-8")
    assert '"poll_source": "github"' in html


def test_build_default_pollsource_is_github(tmp_path):
    """HB-078: when pollSource is absent, default 'github' applies."""
    for folder in ("backlog", "in-progress", "done", "blocked", "not-doing", "feature-sets"):
        (tmp_path / "horde-of-bots" / folder).mkdir(parents=True)

    write(tmp_path, "horde-of-bots/backlog/CM-001-1000.md", FULL_TICKET)

    shutil.copy(REPO_ROOT / "horde-of-bots" / "build.sh", tmp_path / "horde-of-bots" / "build.sh")
    shutil.copy(REPO_ROOT / "horde-of-bots" / "build_lib.py", tmp_path / "horde-of-bots" / "build_lib.py")
    shutil.copy(REPO_ROOT / "horde-of-bots" / "validate.py", tmp_path / "horde-of-bots" / "validate.py")

    result = subprocess.run(["bash", "horde-of-bots/build.sh"], cwd=tmp_path, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr

    html = (tmp_path / "horde-of-bots" / "board.html").read_text(encoding="utf-8")
    assert '"poll_source": "github"' in html


def test_build_renders_stale_claim_machinery(tmp_path):
    """HB-077: stale-claim render plumbing is wired into the generated HTML."""
    for folder in ("backlog", "in-progress", "done", "blocked", "not-doing", "feature-sets"):
        (tmp_path / "horde-of-bots" / folder).mkdir(parents=True)

    write(tmp_path, "horde-of-bots/backlog/CM-001-1000.md", FULL_TICKET)

    shutil.copy(REPO_ROOT / "horde-of-bots" / "build.sh", tmp_path / "horde-of-bots" / "build.sh")
    shutil.copy(REPO_ROOT / "horde-of-bots" / "build_lib.py", tmp_path / "horde-of-bots" / "build_lib.py")
    shutil.copy(REPO_ROOT / "horde-of-bots" / "validate.py", tmp_path / "horde-of-bots" / "validate.py")

    result = subprocess.run(["bash", "horde-of-bots/build.sh"], cwd=tmp_path, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr

    html = (tmp_path / "horde-of-bots" / "board.html").read_text(encoding="utf-8")
    # Helpers and CSS classes must be in the generated bundle even when there
    # are no in-progress tickets to render — so they're available the moment
    # one shows up.
    assert "parseStartedDate" in html
    assert "relativeAgo" in html
    assert "card-stale-meta" in html
    assert "stale-claim" in html
    # stale_after_hours is exposed on D so the JS can read it
    assert "stale_after_hours" in html


def test_build_renders_ready_only_filter_toggle(tmp_path):
    """HB-075: the Ready-only filter toggle is wired into the filter bar."""
    for folder in ("backlog", "in-progress", "done", "blocked", "not-doing", "feature-sets"):
        (tmp_path / "horde-of-bots" / folder).mkdir(parents=True)

    write(tmp_path, "horde-of-bots/backlog/CM-001-1000.md", FULL_TICKET)

    shutil.copy(REPO_ROOT / "horde-of-bots" / "build.sh", tmp_path / "horde-of-bots" / "build.sh")
    shutil.copy(REPO_ROOT / "horde-of-bots" / "build_lib.py", tmp_path / "horde-of-bots" / "build_lib.py")
    shutil.copy(REPO_ROOT / "horde-of-bots" / "validate.py", tmp_path / "horde-of-bots" / "validate.py")

    result = subprocess.run(["bash", "horde-of-bots/build.sh"], cwd=tmp_path, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr

    html = (tmp_path / "horde-of-bots" / "board.html").read_text(encoding="utf-8")
    # Toggle button is in the filter bar
    assert 'id="flt-ready-only"' in html
    assert 'Ready only' in html
    assert 'toggleReadyOnly()' in html
    # Filter logic + state plumbing
    assert 'readyOnly' in html
    assert 'toggleReadyOnly' in html


def test_build_hides_rejected_button_when_no_not_doing_tickets(tmp_path):
    for folder in ("backlog", "in-progress", "done", "blocked", "not-doing", "feature-sets"):
        (tmp_path / "horde-of-bots" / folder).mkdir(parents=True)

    write(tmp_path, "horde-of-bots/backlog/CM-001-1000.md", FULL_TICKET)

    shutil.copy(REPO_ROOT / "horde-of-bots" / "build.sh", tmp_path / "horde-of-bots" / "build.sh")
    shutil.copy(REPO_ROOT / "horde-of-bots" / "build_lib.py", tmp_path / "horde-of-bots" / "build_lib.py")
    shutil.copy(REPO_ROOT / "horde-of-bots" / "validate.py", tmp_path / "horde-of-bots" / "validate.py")

    result = subprocess.run(["bash", "horde-of-bots/build.sh"], cwd=tmp_path, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr

    html = (tmp_path / "horde-of-bots" / "board.html").read_text(encoding="utf-8")
    # Button should be rendered but hidden (display:none when no not-doing tickets)
    assert 'style="display:none"' in html


# ---------- relationship fields: orphan + cycle warnings ----------

def _write_min_ticket(path, hb_id, title, extra_bullets=""):
    body = f"""# [{hb_id}] {title}

- **Status**: open
{extra_bullets}
## Goal
g
"""
    path.write_text(body, encoding="utf-8")


def _stage_repo(tmp_path):
    for folder in ("backlog", "in-progress", "done", "blocked", "not-doing", "feature-sets"):
        (tmp_path / "horde-of-bots" / folder).mkdir(parents=True, exist_ok=True)
    shutil.copy(REPO_ROOT / "horde-of-bots" / "build.sh", tmp_path / "horde-of-bots" / "build.sh")
    shutil.copy(REPO_ROOT / "horde-of-bots" / "build_lib.py", tmp_path / "horde-of-bots" / "build_lib.py")
    shutil.copy(REPO_ROOT / "horde-of-bots" / "validate.py", tmp_path / "horde-of-bots" / "validate.py")


def test_build_warns_on_orphan_reference_and_still_exits_zero(tmp_path):
    _stage_repo(tmp_path)
    _write_min_ticket(
        tmp_path / "horde-of-bots/backlog/CM-001-1000.md",
        "CM-001", "Orphan owner",
        "- **Related**: CM-999\n- **Blocks**: CM-888\n",
    )

    result = subprocess.run(["bash", "horde-of-bots/build.sh"], cwd=tmp_path, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert "CM-999" in result.stderr
    assert "CM-888" in result.stderr
    assert "does not exist" in result.stderr
    assert (tmp_path / "horde-of-bots" / "board.html").exists()


def test_build_warns_on_cycle_and_still_exits_zero(tmp_path):
    _stage_repo(tmp_path)
    _write_min_ticket(
        tmp_path / "horde-of-bots/backlog/CM-001-1000.md",
        "CM-001", "A",
        "- **Blocks**: CM-002\n",
    )
    _write_min_ticket(
        tmp_path / "horde-of-bots/backlog/CM-002-1001.md",
        "CM-002", "B",
        "- **Blocks**: CM-001\n",
    )

    result = subprocess.run(["bash", "horde-of-bots/build.sh"], cwd=tmp_path, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert "cycle detected" in result.stderr
    assert "CM-001" in result.stderr and "CM-002" in result.stderr
    assert (tmp_path / "horde-of-bots" / "board.html").exists()


def test_build_inverse_blocked_by_inferred_is_rendered(tmp_path):
    """CM-001 Blocks CM-002. CM-002's card HTML should show a 'blocked_by_inferred' reference to CM-001."""
    _stage_repo(tmp_path)
    _write_min_ticket(
        tmp_path / "horde-of-bots/backlog/CM-001-1000.md",
        "CM-001", "Upstream",
        "- **Blocks**: CM-002\n",
    )
    _write_min_ticket(
        tmp_path / "horde-of-bots/backlog/CM-002-1001.md",
        "CM-002", "Downstream",
    )

    result = subprocess.run(["bash", "horde-of-bots/build.sh"], cwd=tmp_path, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    html = (tmp_path / "horde-of-bots" / "board.html").read_text(encoding="utf-8")
    # The embedded JSON data should contain the inferred field populated for CM-002
    assert '"blocked_by_inferred"' in html
    # And the upstream's explicit blocks list should be there too
    assert '"blocks"' in html


def test_in_progress_card_renders_hb_robot(tmp_path):
    """In-progress tickets should have the .hb-robot perimeter-walking element. Backlog tickets should not."""
    _stage_repo(tmp_path)
    _write_min_ticket(
        tmp_path / "horde-of-bots/in-progress/CM-001-1000.md",
        "CM-001", "Active work",
        "- **Status**: in-progress\n",
    )
    _write_min_ticket(
        tmp_path / "horde-of-bots/backlog/CM-002-1001.md",
        "CM-002", "Just sitting",
    )

    result = subprocess.run(["bash", "horde-of-bots/build.sh"], cwd=tmp_path, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    html = (tmp_path / "horde-of-bots" / "board.html").read_text(encoding="utf-8")
    # Robot CSS class and keyframes are always present in the stylesheet
    assert ".hb-robot" in html
    assert "@keyframes hb-robot-walk" in html
    # The renderer JS conditionally injects the robot only for in-progress tickets
    assert "t.status === 'in-progress'" in html and "hb-robot" in html
    # And the legacy pulse keyframes should be gone
    assert "cm-active-pulse" not in html
