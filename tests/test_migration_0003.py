"""Static analysis of supabase/migrations/0003_locks_select_policy.sql.

Mirrors tests/test_migration_sql.py — catches regressions in the locks
SELECT policy migration without needing a live database.
"""
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent
MIGRATION = ROOT / "supabase" / "migrations" / "0003_locks_select_policy.sql"


@pytest.fixture(scope="module")
def sql():
    assert MIGRATION.exists(), f"{MIGRATION} is missing"
    return MIGRATION.read_text(encoding="utf-8").lower()


def _strip_comments_and_blank(text):
    keep = []
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("--"):
            continue
        keep.append(s)
    return keep


def test_wrapped_in_transaction(sql):
    lines = _strip_comments_and_blank(sql)
    assert lines[0] == "begin;"
    assert lines[-1] == "commit;"


def test_drops_policy_before_creating(sql):
    assert re.search(
        r"drop policy if exists\s+locks_select_all\s+on\s+public\.locks",
        sql,
    ), "must drop policy idempotently before creating"


def test_creates_select_policy_for_anon_and_authenticated(sql):
    assert re.search(
        r"create policy\s+locks_select_all\s+on\s+public\.locks\s+for\s+select\s+to\s+anon,\s*authenticated",
        sql,
    ), "must create SELECT policy for anon and authenticated"


def test_policy_uses_true(sql):
    assert re.search(
        r"using\s*\(\s*true\s*\)",
        sql,
    ), "policy must use (true) — locks data is not sensitive"


def test_grants_select_to_anon_and_authenticated(sql):
    assert re.search(
        r"grant\s+select\s+on\s+public\.locks\s+to\s+anon,\s*authenticated",
        sql,
    ), "must GRANT SELECT on locks to anon and authenticated"
