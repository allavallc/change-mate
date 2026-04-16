"""Static analysis of supabase/migrations/0002_ticket_id_sequence.sql.

Mirrors tests/test_migration_sql.py — catches regressions in the sequence
migration without needing a live database.
"""
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent
MIGRATION = ROOT / "supabase" / "migrations" / "0002_ticket_id_sequence.sql"


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


def test_sequence_created_idempotently_starting_at_12(sql):
    assert re.search(
        r"create sequence if not exists\s+public\.ticket_id_seq\b",
        sql,
    ), "missing idempotent CREATE SEQUENCE"
    assert re.search(r"start with\s+12\b", sql), "sequence must start with 12"


def test_sequence_revoked_from_public_and_unprivileged_roles(sql):
    assert re.search(
        r"revoke all on sequence\s+public\.ticket_id_seq\s+from\s+public",
        sql,
    )
    assert re.search(
        r"revoke all on sequence\s+public\.ticket_id_seq\s+from\s+anon,\s+authenticated",
        sql,
    )


def test_claim_ticket_id_function_exists(sql):
    assert re.search(
        r"create or replace function\s+public\.claim_ticket_id\s*\(\s*\)\s+returns\s+bigint",
        sql,
    ), "missing claim_ticket_id function definition"


def test_claim_ticket_id_is_security_definer(sql):
    # Function body must include `security definer` to bypass caller's RLS.
    assert re.search(r"security\s+definer", sql), "claim_ticket_id must be SECURITY DEFINER"


def test_claim_ticket_id_has_locked_search_path(sql):
    # SECURITY DEFINER + unlocked search_path is a classic Postgres exploit vector.
    assert re.search(
        r"set\s+search_path\s*=\s*public",
        sql,
    ), "SECURITY DEFINER function must pin search_path"


def test_claim_ticket_id_calls_nextval_on_sequence(sql):
    assert re.search(
        r"select\s+nextval\s*\(\s*'public\.ticket_id_seq'\s*\)",
        sql,
    )


def test_claim_ticket_id_execute_granted_only_to_service_role(sql):
    # Revokes for public + anon/authenticated MUST come before the grant.
    revoke_public = sql.find("revoke all on function public.claim_ticket_id() from public")
    revoke_anon = sql.find(
        "revoke all on function public.claim_ticket_id() from anon, authenticated"
    )
    grant_svc = sql.find(
        "grant execute on function public.claim_ticket_id() to service_role"
    )
    assert revoke_public != -1, "missing REVOKE ALL from public on claim_ticket_id"
    assert revoke_anon != -1, "missing REVOKE ALL from anon, authenticated on claim_ticket_id"
    assert grant_svc != -1, "missing GRANT EXECUTE to service_role on claim_ticket_id"
    assert revoke_public < grant_svc
    assert revoke_anon < grant_svc
