import json

import pytest

import verify_supabase as vs


@pytest.fixture
def good_config(tmp_path, monkeypatch):
    cfg = {
        "gist_id": "",
        "project_name": "test",
        "supabase_url": "https://example.supabase.co",
        "supabase_publishable_key": "sb_publishable_TEST",
    }
    (tmp_path / "change-mate-config.json").write_text(json.dumps(cfg), encoding="utf-8")
    monkeypatch.chdir(tmp_path)
    return cfg


@pytest.fixture(autouse=True)
def _no_real_sleep(monkeypatch):
    monkeypatch.setattr(vs.time, "sleep", lambda _s: None)


# ---------- load_config ----------


def test_load_config_missing_file(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    with pytest.raises(SystemExit) as exc:
        vs.load_config()
    assert exc.value.code == 1
    assert "not found" in capsys.readouterr().out


def test_load_config_invalid_json(tmp_path, monkeypatch, capsys):
    (tmp_path / "change-mate-config.json").write_text("{not json", encoding="utf-8")
    monkeypatch.chdir(tmp_path)
    with pytest.raises(SystemExit) as exc:
        vs.load_config()
    assert exc.value.code == 1
    assert "not valid JSON" in capsys.readouterr().out


def test_load_config_missing_url(tmp_path, monkeypatch, capsys):
    (tmp_path / "change-mate-config.json").write_text(
        json.dumps({"supabase_publishable_key": "k"}), encoding="utf-8"
    )
    monkeypatch.chdir(tmp_path)
    with pytest.raises(SystemExit) as exc:
        vs.load_config()
    assert exc.value.code == 1
    assert "supabase_url" in capsys.readouterr().out


def test_load_config_missing_key(tmp_path, monkeypatch, capsys):
    (tmp_path / "change-mate-config.json").write_text(
        json.dumps({"supabase_url": "https://x.supabase.co"}), encoding="utf-8"
    )
    monkeypatch.chdir(tmp_path)
    with pytest.raises(SystemExit) as exc:
        vs.load_config()
    assert exc.value.code == 1
    assert "supabase_publishable_key" in capsys.readouterr().out


def test_load_config_strips_trailing_slash(good_config):
    good_config["supabase_url"] = "https://example.supabase.co/"
    from pathlib import Path as _P
    _P("change-mate-config.json").write_text(json.dumps(good_config), encoding="utf-8")
    url, key = vs.load_config()
    assert url == "https://example.supabase.co"
    assert key == "sb_publishable_TEST"


# ---------- request (retry wrapper) ----------


def _fake_single(monkeypatch, responses):
    """Install a _single_request stub that pops responses in order."""
    calls = {"count": 0}

    def fake(url, key, method="GET", body=None):
        calls["count"] += 1
        return responses.pop(0)

    monkeypatch.setattr(vs, "_single_request", fake)
    return calls


def test_request_returns_success_without_retry(monkeypatch):
    calls = _fake_single(monkeypatch, [(200, "[]")])
    status, body = vs.request("https://x", "k")
    assert (status, body) == (200, "[]")
    assert calls["count"] == 1


def test_request_retries_on_pgrst002_then_succeeds(monkeypatch):
    responses = [
        (503, '{"code":"PGRST002","message":"cold"}'),
        (503, '{"code":"PGRST002","message":"cold"}'),
        (200, "[]"),
    ]
    calls = _fake_single(monkeypatch, responses)
    status, body = vs.request("https://x", "k")
    assert status == 200
    assert calls["count"] == 3


def test_request_gives_up_after_max_retries_on_persistent_pgrst002(monkeypatch):
    responses = [(503, '{"code":"PGRST002"}')] * (vs.SCHEMA_CACHE_RETRIES + 1)
    calls = _fake_single(monkeypatch, list(responses))
    status, body = vs.request("https://x", "k")
    assert status == 503
    assert "PGRST002" in body
    assert calls["count"] == vs.SCHEMA_CACHE_RETRIES + 1


def test_request_does_not_retry_on_other_errors(monkeypatch):
    calls = _fake_single(monkeypatch, [(500, "boom")])
    status, body = vs.request("https://x", "k")
    assert (status, body) == (500, "boom")
    assert calls["count"] == 1


# ---------- individual checks ----------


def test_write_keys_hidden_empty_array_passes(monkeypatch):
    _fake_single(monkeypatch, [(200, "[]")])
    ok, _ = vs.check_write_keys_hidden("https://x", "k")
    assert ok


def test_write_keys_hidden_permission_denied_passes(monkeypatch):
    _fake_single(monkeypatch, [(401, "permission denied for table write_keys")])
    ok, _ = vs.check_write_keys_hidden("https://x", "k")
    assert ok


def test_write_keys_hidden_rows_returned_fails(monkeypatch):
    _fake_single(monkeypatch, [(200, '[{"key_hash":"abc"}]')])
    ok, detail = vs.check_write_keys_hidden("https://x", "k")
    assert not ok
    assert "200" in detail


def test_locks_insert_blocked_on_403_passes(monkeypatch):
    _fake_single(monkeypatch, [(403, "denied")])
    ok, _ = vs.check_locks_insert_blocked("https://x", "k")
    assert ok


def test_locks_insert_blocked_on_201_fails(monkeypatch):
    _fake_single(monkeypatch, [(201, "created")])
    ok, detail = vs.check_locks_insert_blocked("https://x", "k")
    assert not ok
    assert "201" in detail


def test_ticket_events_readable_on_200_passes(monkeypatch):
    _fake_single(monkeypatch, [(200, "[]")])
    ok, _ = vs.check_ticket_events_readable("https://x", "k")
    assert ok


def test_ticket_events_readable_on_401_fails(monkeypatch):
    _fake_single(monkeypatch, [(401, "denied")])
    ok, detail = vs.check_ticket_events_readable("https://x", "k")
    assert not ok
    assert "401" in detail


# ---------- main orchestrator ----------


def test_main_all_pass_exits_zero(good_config, monkeypatch, capsys):
    _fake_single(monkeypatch, [
        (200, "[]"),      # write_keys
        (403, "denied"),  # locks insert
        (200, "[]"),      # ticket_events
    ])
    with pytest.raises(SystemExit) as exc:
        vs.main()
    assert exc.value.code == 0
    assert "All checks passed" in capsys.readouterr().out


def test_main_all_pgrst002_exits_two(good_config, monkeypatch, capsys):
    # Every call returns PGRST002, for every check. SCHEMA_CACHE_RETRIES+1 calls per check × 3 checks.
    total = (vs.SCHEMA_CACHE_RETRIES + 1) * 3
    _fake_single(monkeypatch, [(503, '{"code":"PGRST002","message":"cold"}')] * total)
    with pytest.raises(SystemExit) as exc:
        vs.main()
    assert exc.value.code == 2
    out = capsys.readouterr().out
    assert "schema cache is cold" in out.lower()
    assert "paused" in out.lower()


def test_main_some_failures_exits_one(good_config, monkeypatch, capsys):
    _fake_single(monkeypatch, [
        (200, '[{"key_hash":"leaked"}]'),  # write_keys LEAKS — fail
        (403, "denied"),                    # locks blocked — pass
        (200, "[]"),                        # ticket_events — pass
    ])
    with pytest.raises(SystemExit) as exc:
        vs.main()
    assert exc.value.code == 1
    out = capsys.readouterr().out
    assert "[FAIL]" in out
    assert "Re-apply" in out
