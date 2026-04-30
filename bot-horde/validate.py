#!/usr/bin/env python3
"""Validate every committed ticket against the schema.

Wired into build.sh so CI fails on malformed tickets. Catches the class of
bugs where a ticket's frontmatter disagrees with its folder (e.g. BH-060
sat in backlog/ for two days with Status: in-progress because nothing
checked).

Run: `python3 bot-horde/validate.py` from repo root.
"""
import json
import os
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from build_lib import parse_ticket


VERIFICATION_VALUES = {"bot-claimed", "tests-passed", "bot-reviewed", "human-reviewed"}
FAILURE_MODE_VALUES = {"failed-tests", "merge-conflict", "context-exceeded", "unmet-dep", "needs-human"}
DATE_FORMATS = ("%Y-%m-%d", "%Y-%m-%d %H:%M")
FOLDER_TO_STATUS = {
    "backlog": "open",
    "in-progress": "in-progress",
    "done": "done",
    "blocked": "blocked",
    "not-doing": "not-doing",
}


def _parse_date(s):
    """Return datetime if parseable, None if empty, False if malformed."""
    s = (s or "").strip()
    if not s:
        return None
    for fmt in DATE_FORMATS:
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            continue
    return False


def validate(repo_root):
    """Walk the ticket tree and return (errors, ticket_count)."""
    repo_root = Path(repo_root)
    base = repo_root / "bot-horde"
    if not base.exists():
        return ([], 0)

    config_path = base / "config.json"
    prefix = "HB"
    if config_path.exists():
        try:
            prefix = json.loads(config_path.read_text(encoding="utf-8")).get("ticket_prefix", "HB")
        except (json.JSONDecodeError, OSError):
            pass

    errors = []
    by_id = {}

    for folder, expected_status in FOLDER_TO_STATUS.items():
        d = base / folder
        if not d.exists():
            continue
        for f in sorted(d.glob(f"{prefix}-*.md")):
            t = parse_ticket(f, expected_status, prefix=prefix)
            by_id[t["id"]] = {"folder": folder, "ticket": t, "path": f}

    for tid, info in by_id.items():
        folder = info["folder"]
        t = info["ticket"]
        try:
            path_str = str(info["path"].relative_to(repo_root))
        except ValueError:
            path_str = str(info["path"])
        prefix_msg = f"{path_str}:"

        # Required fields
        if not (t.get("priority") or "").strip():
            errors.append(f"{prefix_msg} missing required field 'Priority'")
        if not (t.get("effort") or "").strip():
            errors.append(f"{prefix_msg} missing required field 'Effort'")
        if not (t.get("status") or "").strip():
            errors.append(f"{prefix_msg} missing required field 'Status'")

        # Status matches folder
        expected = FOLDER_TO_STATUS[folder]
        actual = (t.get("status") or "").strip()
        if actual and actual != expected:
            errors.append(
                f"{prefix_msg} Status='{actual}' but ticket is in '{folder}/' "
                f"(expected '{expected}')"
            )

        # Dates parseable
        for field, label in (("started", "Started"), ("completed", "Completed")):
            v = (t.get(field) or "").strip()
            if v:
                d = _parse_date(v)
                if d is False:
                    errors.append(
                        f"{prefix_msg} {label}='{v}' is not a parseable date "
                        f"(expected YYYY-MM-DD or YYYY-MM-DD HH:MM)"
                    )

        # Folder-specific required fields
        if folder in ("in-progress", "done"):
            if not (t.get("assigned_to") or "").strip():
                errors.append(
                    f"{prefix_msg} 'Assigned to' is required for tickets in '{folder}/'"
                )

        if folder == "done":
            if not (t.get("completed") or "").strip():
                errors.append(f"{prefix_msg} 'Completed' is required for tickets in 'done/'")
            verif = (t.get("verification") or "").strip()
            if not verif:
                errors.append(
                    f"{prefix_msg} 'Verification' is required for tickets in 'done/' "
                    f"(one of: {sorted(VERIFICATION_VALUES)})"
                )
            elif verif not in VERIFICATION_VALUES:
                errors.append(
                    f"{prefix_msg} Verification='{verif}' is not in allowed set "
                    f"{sorted(VERIFICATION_VALUES)}"
                )

        if folder == "blocked":
            fmode = (t.get("failure_mode") or "").strip()
            if not fmode:
                errors.append(
                    f"{prefix_msg} 'Failure mode' is required for tickets in 'blocked/' "
                    f"(one of: {sorted(FAILURE_MODE_VALUES)})"
                )
            elif fmode not in FAILURE_MODE_VALUES:
                errors.append(
                    f"{prefix_msg} Failure mode='{fmode}' is not in allowed set "
                    f"{sorted(FAILURE_MODE_VALUES)}"
                )

        # Reference resolution
        for field in ("related", "blocks", "blocked_by", "split_from"):
            for ref in t.get(field, []):
                if ref not in by_id:
                    errors.append(
                        f"{prefix_msg} {field} references '{ref}' but no such ticket exists"
                    )

        # Done with unmet deps (BH-075)
        if folder == "done":
            for ref in t.get("blocked_by", []):
                ref_info = by_id.get(ref)
                if ref_info and ref_info["folder"] != "done":
                    errors.append(
                        f"{prefix_msg} cannot be in 'done/' while Blocked-by "
                        f"'{ref}' is still in '{ref_info['folder']}/'"
                    )

    return errors, len(by_id)


def main():
    if os.environ.get("BOTHORDE_DEMO", "").lower() in ("1", "true", "yes"):
        print("[validate] skipped (demo mode)")
        return 0

    repo_root = Path(__file__).parent.parent
    errors, count = validate(repo_root)
    if errors:
        for e in errors:
            print(f"[validate] {e}", file=sys.stderr)
        print(
            f"\n[validate] {len(errors)} error(s) across {count} tickets",
            file=sys.stderr,
        )
        return 1
    print(f"[validate] OK — {count} tickets pass schema validation")
    return 0


if __name__ == "__main__":
    sys.exit(main())
