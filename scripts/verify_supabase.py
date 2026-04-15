#!/usr/bin/env python3
"""Verify Supabase RLS is correctly blocking anon writes to change-mate tables.

Reads `supabase_url` and `supabase_publishable_key` from change-mate-config.json
in the current directory, then hits the REST API with the anon key and checks:

    GET  /rest/v1/write_keys     -> empty array or 401/403  (anon cannot read keys)
    POST /rest/v1/locks          -> 401/403                 (anon cannot write locks)
    GET  /rest/v1/ticket_events  -> 200                     (anon CAN read events)

Exit 0 if all three pass, 1 otherwise. Pure stdlib — no pip install required.
"""
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

CONFIG_PATH = Path("change-mate-config.json")
TIMEOUT_SEC = 10
SCHEMA_CACHE_RETRIES = 5
SCHEMA_CACHE_DELAY_SEC = 4


def load_config():
    if not CONFIG_PATH.exists():
        print(f"[FAIL] {CONFIG_PATH} not found — run this from the repo root.")
        sys.exit(1)
    try:
        cfg = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        print(f"[FAIL] {CONFIG_PATH} is not valid JSON: {e}")
        sys.exit(1)
    url = (cfg.get("supabase_url") or "").rstrip("/")
    key = cfg.get("supabase_publishable_key") or ""
    missing = [n for n, v in (("supabase_url", url), ("supabase_publishable_key", key)) if not v]
    if missing:
        print(f"[FAIL] Missing {' and '.join(missing)} in {CONFIG_PATH}. See SETUP.md step 2.3.")
        sys.exit(1)
    return url, key


def _single_request(url, key, method="GET", body=None):
    headers = {"apikey": key, "Authorization": f"Bearer {key}"}
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, method=method, headers=headers, data=data)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_SEC) as resp:
            return resp.status, resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")
    except urllib.error.URLError as e:
        return None, f"network error: {e.reason}"


def request(url, key, method="GET", body=None):
    # Supabase PostgREST returns 503 with code PGRST002 for up to a minute
    # after a migration while it refreshes its schema cache. Retry transparently.
    warned = False
    for attempt in range(SCHEMA_CACHE_RETRIES + 1):
        status, out = _single_request(url, key, method=method, body=body)
        if status == 503 and "PGRST002" in (out or "") and attempt < SCHEMA_CACHE_RETRIES:
            if not warned:
                print("       (Supabase schema cache warming up, waiting...)")
                warned = True
            time.sleep(SCHEMA_CACHE_DELAY_SEC)
            continue
        return status, out
    return status, out


def trunc(s, n=180):
    s = s.strip().replace("\n", " ")
    return s if len(s) <= n else s[:n] + "..."


def check_write_keys_hidden(base, key):
    status, body = request(f"{base}/rest/v1/write_keys?select=*", key)
    if status == 200 and body.strip() in ("[]", ""):
        return True, f"HTTP 200, empty body (RLS hides rows)"
    if status in (401, 403):
        return True, f"HTTP {status} (RLS denies read): {trunc(body)}"
    return False, f"HTTP {status}: {trunc(body)}"


def check_locks_insert_blocked(base, key):
    status, body = request(
        f"{base}/rest/v1/locks",
        key,
        method="POST",
        body={"ticket_id": "CM-VERIFY", "agent": "verify_supabase.py"},
    )
    if status in (401, 403):
        return True, f"HTTP {status} (insert denied): {trunc(body)}"
    return False, f"HTTP {status}: {trunc(body)}"


def check_ticket_events_readable(base, key):
    status, body = request(f"{base}/rest/v1/ticket_events?select=*&limit=1", key)
    if status == 200:
        return True, f"HTTP 200: {trunc(body)}"
    return False, f"HTTP {status}: {trunc(body)}"


def main():
    base, key = load_config()
    print(f"Probing {base} with publishable/anon key...\n")

    checks = [
        ("write_keys is hidden from anon",      check_write_keys_hidden),
        ("locks rejects anon INSERT",           check_locks_insert_blocked),
        ("ticket_events is readable by anon",   check_ticket_events_readable),
    ]
    results = []
    for label, fn in checks:
        ok, detail = fn(base, key)
        mark = "[PASS]" if ok else "[FAIL]"
        print(f"{mark} {label}")
        print(f"       {detail}\n")
        results.append((ok, detail))

    all_pass = all(ok for ok, _ in results)
    if all_pass:
        print("All checks passed. RLS is correctly configured.")
        sys.exit(0)

    all_schema_cache = all((not ok) and "PGRST002" in detail for ok, detail in results)
    if all_schema_cache:
        print("Supabase is not responding yet (PostgREST schema cache is cold).")
        print("Likely causes:")
        print("  - Project was just created and is still spinning up — wait 1-2 minutes and re-run.")
        print("  - Project is paused (free tier pauses after ~1 week of inactivity).")
        print("    Unpause it at https://supabase.com/dashboard, then re-run.")
        sys.exit(2)

    print("One or more checks failed. Re-apply supabase/migrations/0001_initial.sql and retry.")
    sys.exit(1)


if __name__ == "__main__":
    main()
