"""Tests for setup.sh — the local-only-mode gating in particular.

Local-only mode is signaled by `horde-of-bots/` appearing in `.gitignore`. In that
mode `setup.sh` must NOT install `.github/workflows/horde-of-bots-rebuild-board.yml`
(the workflow runs `bash horde-of-bots/build.sh` in CI, which fails when
`horde-of-bots/` is gitignored). Re-running setup.sh should also detect a stale
workflow and offer to remove it.

These tests pre-create every managed horde-of-bots file in a tmp working dir so
`setup.sh`'s `download()` helper short-circuits — network is not required for
the gating logic.
"""
import os
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).parent.parent

MANAGED_HB_FILES = (
    "HORDEOFBOTS.md",
    "INSTALL-FAQ.md",
    "UPDATING.md",
    "MANIFEST.json",
    "build.sh",
    "build_lib.py",
    "config.json",
)

WORKFLOW_REL = ".github/workflows/horde-of-bots-rebuild-board.yml"


def _stage_repo(tmp_path: Path, gitignore_contents: str, with_workflow: bool = False) -> None:
    hb_dir = tmp_path / "horde-of-bots"
    hb_dir.mkdir()
    for name in MANAGED_HB_FILES:
        (hb_dir / name).write_text("placeholder", encoding="utf-8")
    (tmp_path / ".gitignore").write_text(gitignore_contents, encoding="utf-8")
    if with_workflow:
        wf = tmp_path / WORKFLOW_REL
        wf.parent.mkdir(parents=True)
        wf.write_text("on: push\n", encoding="utf-8")
    shutil.copy(REPO_ROOT / "setup.sh", tmp_path / "setup.sh")


def _run_setup(tmp_path: Path, env_overrides: dict) -> subprocess.CompletedProcess:
    """Run setup.sh in tmp_path. Env overrides are inlined into the bash command
    rather than passed via subprocess env=, because Git Bash on Windows does not
    reliably surface Python-set env keys to the script."""
    fake_home = tmp_path / "fake_home"
    fake_home.mkdir(exist_ok=True)
    inline_env = " ".join(f"{k}={v}" for k, v in env_overrides.items())
    inline_env = f"HOME='{fake_home.as_posix()}' " + (inline_env + " " if inline_env else "")
    cmd = f"{inline_env}bash setup.sh"
    return subprocess.run(
        ["bash", "-c", cmd],
        cwd=tmp_path,
        capture_output=True,
        text=True,
        stdin=subprocess.DEVNULL,
    )


def test_local_only_mode_skips_workflow_install(tmp_path):
    """In local-only mode with no existing workflow, setup.sh must not download one."""
    _stage_repo(tmp_path, "horde-of-bots/\n")

    result = _run_setup(tmp_path, {})

    assert result.returncode == 0, \
        f"setup.sh failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert not (tmp_path / WORKFLOW_REL).exists(), \
        "rebuild-board workflow must not be installed in local-only mode"
    assert "local-only mode detected" in result.stdout


def test_local_only_mode_offers_to_remove_existing_workflow(tmp_path):
    """An adopter who installed before the fix has a stale workflow. Re-running
    setup.sh in local-only mode with HORDEOFBOTS_REMOVE_WORKFLOW=yes removes it."""
    _stage_repo(tmp_path, "horde-of-bots/\n", with_workflow=True)

    result = _run_setup(tmp_path, {"HORDEOFBOTS_REMOVE_WORKFLOW": "yes"})

    assert result.returncode == 0, \
        f"setup.sh failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert not (tmp_path / WORKFLOW_REL).exists(), "stale workflow should have been removed"


def test_local_only_mode_keeps_workflow_when_removal_declined(tmp_path):
    """If the user declines removal, the workflow stays (with a warning)."""
    _stage_repo(tmp_path, "horde-of-bots/\n", with_workflow=True)

    result = _run_setup(tmp_path, {"HORDEOFBOTS_REMOVE_WORKFLOW": "no"})

    assert result.returncode == 0
    assert (tmp_path / WORKFLOW_REL).exists(), "workflow should be kept when user declines"


def test_local_only_mode_adds_marker_comment_to_gitignore(tmp_path):
    """setup.sh writes a one-line marker explaining why no workflow is installed."""
    _stage_repo(tmp_path, "horde-of-bots/\n")

    result = _run_setup(tmp_path, {})
    assert result.returncode == 0

    gi = (tmp_path / ".gitignore").read_text(encoding="utf-8")
    assert "local-only mode" in gi
    assert "rebuild-board workflow intentionally not installed" in gi


def test_local_only_mode_detection_ignores_unrelated_lines(tmp_path):
    """A .gitignore that mentions horde-of-bots in a comment or a partial-match
    pattern (e.g. horde-of-bots-output/, foo/horde-of-bots/) must NOT trigger
    local-only mode. Pre-create the workflow so download() skips network."""
    _stage_repo(
        tmp_path,
        "# horde-of-bots notes\nhorde-of-bots-output/\nfoo/horde-of-bots/\n",
        with_workflow=True,
    )

    result = _run_setup(tmp_path, {})

    assert result.returncode == 0, \
        f"setup.sh failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert "local-only mode detected" not in result.stdout, \
        "false positive: .gitignore did not contain a true horde-of-bots/ ignore rule"
    assert (tmp_path / WORKFLOW_REL).exists(), "git-sync mode should keep the workflow"
