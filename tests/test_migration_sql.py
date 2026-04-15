"""Static analysis of supabase/migrations/0001_initial.sql.

These tests do not talk to a database. They verify the SQL file's textual shape
is correct — idempotent patterns, expected tables, policies, RLS directives,
and revokes. Protects against accidental regressions when the migration is
edited.
"""
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent
MIGRATION = ROOT / "supabase" / "migrations" / "0001_initial.sql"


@pytest.fixture(scope="module")
def sql():
    assert MIGRATION.exists(), f"{MIGRATION} is missing"
    return MIGRATION.read_text(encoding="utf-8").lower()


def _strip_comments_and_blank(sql_text):
    """Return the SQL with `--` comment lines and blank lines removed."""
    keep = []
    for line in sql_text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("--"):
            continue
        keep.append(stripped)
    return keep


def test_wrapped_in_transaction(sql):
    lines = _strip_comments_and_blank(sql)
    assert lines, "migration appears to be empty after stripping comments"
    assert lines[0] == "begin;", f"first non-comment line must be `begin;`, got {lines[0]!r}"
    assert lines[-1] == "commit;", f"last non-comment line must be `commit;`, got {lines[-1]!r}"


def test_creates_all_three_tables_idempotently(sql):
    for table in ("locks", "ticket_events", "write_keys"):
        pattern = rf"create table if not exists\s+public\.{table}\s*\("
        assert re.search(pattern, sql), f"missing idempotent CREATE TABLE for {table}"


def test_creates_required_indexes_idempotently(sql):
    indexes = [
        "ticket_events_ticket_id_idx",
        "ticket_events_created_at_idx",
        "write_keys_role_idx",
    ]
    for idx in indexes:
        pattern = rf"create index if not exists\s+{idx}\s+on\s+public\."
        assert re.search(pattern, sql), f"missing idempotent CREATE INDEX for {idx}"


def test_rls_enabled_and_forced_on_all_three_tables(sql):
    for table in ("locks", "ticket_events", "write_keys"):
        assert re.search(rf"alter table\s+public\.{table}\s+enable row level security", sql), \
            f"RLS not enabled on {table}"
        assert re.search(rf"alter table\s+public\.{table}\s+force\s+row level security", sql), \
            f"RLS not forced on {table}"


def test_ticket_events_select_policy_exists_and_is_preceded_by_drop(sql):
    drop_idx = sql.find("drop policy if exists ticket_events_select_all")
    create_idx = sql.find("create policy ticket_events_select_all")
    assert drop_idx != -1, "missing DROP POLICY IF EXISTS ticket_events_select_all"
    assert create_idx != -1, "missing CREATE POLICY ticket_events_select_all"
    assert drop_idx < create_idx, "DROP POLICY must precede CREATE POLICY for idempotence"


def test_no_policies_defined_on_locks(sql):
    assert not re.search(r"create policy\s+\w+\s+on\s+public\.locks", sql), \
        "locks must have zero policies (strict deny-all for non-service-role)"


def test_no_policies_defined_on_write_keys(sql):
    assert not re.search(r"create policy\s+\w+\s+on\s+public\.write_keys", sql), \
        "write_keys must have zero policies (service-role only)"


def test_anon_and_authenticated_revoked_on_locks_and_write_keys(sql):
    for table in ("locks", "write_keys"):
        pattern = rf"revoke all on\s+public\.{table}\s+from\s+anon,\s+authenticated"
        assert re.search(pattern, sql), f"missing REVOKE ALL on {table} from anon, authenticated"


def test_anon_can_select_but_not_write_ticket_events(sql):
    assert re.search(
        r"revoke insert, update, delete on\s+public\.ticket_events\s+from\s+anon,\s+authenticated",
        sql,
    ), "missing REVOKE INSERT/UPDATE/DELETE on ticket_events"
    assert re.search(
        r"grant\s+select on\s+public\.ticket_events\s+to\s+anon,\s+authenticated",
        sql,
    ), "missing GRANT SELECT on ticket_events"


def test_write_keys_role_check_constraint(sql):
    assert re.search(r"role\s+text\s+not null\s+check\s*\(role\s+in\s*\(\s*'human'\s*,\s*'agent'\s*\)\s*\)", sql), \
        "missing role check constraint ('human', 'agent') on write_keys"


def test_locks_ticket_id_is_primary_key(sql):
    # Inside the CREATE TABLE locks block, ticket_id must be declared PRIMARY KEY.
    match = re.search(r"create table if not exists\s+public\.locks\s*\((.*?)\);", sql, re.DOTALL)
    assert match, "could not locate locks CREATE TABLE block"
    body = match.group(1)
    assert re.search(r"ticket_id\s+text\s+primary key", body), \
        "locks.ticket_id must be the PRIMARY KEY to guarantee atomic claims"
