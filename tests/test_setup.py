"""Tests for setup.sh — the local-only-mode gating in particular.

Local-only mode is signaled by `bot-horde/` appearing in `.gitignore`. In that
mode `setup.sh` must NOT install `.github/workflows/bot-horde-rebuild-board.yml`
(the workflow runs `bash bot-horde/build.sh` in CI, which fails when
`bot-horde/` is gitignored). Re-running setup.sh should also detect a stale
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
    "BOTHORDE.md",
    "INSTALL-FAQ.md",
    "UPDATING.md",
    "MANIFEST.json",
    "build.sh",
    "build_lib.py",
    "config.json",
)

WORKFLOW_REL = ".github/workflows/bot-horde-rebuild-board.yml"


def _stage_repo(tmp_path: Path, gitignore_contents: str, with_workflow: bool = False) -> None:
    hb_dir = tmp_path / "bot-horde"
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
    _stage_repo(tmp_path, "bot-horde/\n")

    result = _run_setup(tmp_path, {})

    assert result.returncode == 0, \
        f"setup.sh failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert not (tmp_path / WORKFLOW_REL).exists(), \
        "rebuild-board workflow must not be installed in local-only mode"
    assert "local-only mode detected" in result.stdout


def test_local_only_mode_offers_to_remove_existing_workflow(tmp_path):
    """An adopter who installed before the fix has a stale workflow. Re-running
    setup.sh in local-only mode with BOTHORDE_REMOVE_WORKFLOW=yes removes it."""
    _stage_repo(tmp_path, "bot-horde/\n", with_workflow=True)

    result = _run_setup(tmp_path, {"BOTHORDE_REMOVE_WORKFLOW": "yes"})

    assert result.returncode == 0, \
        f"setup.sh failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert not (tmp_path / WORKFLOW_REL).exists(), "stale workflow should have been removed"


def test_local_only_mode_keeps_workflow_when_removal_declined(tmp_path):
    """If the user declines removal, the workflow stays (with a warning)."""
    _stage_repo(tmp_path, "bot-horde/\n", with_workflow=True)

    result = _run_setup(tmp_path, {"BOTHORDE_REMOVE_WORKFLOW": "no"})

    assert result.returncode == 0
    assert (tmp_path / WORKFLOW_REL).exists(), "workflow should be kept when user declines"


def test_local_only_mode_adds_marker_comment_to_gitignore(tmp_path):
    """setup.sh writes a one-line marker explaining why no workflow is installed."""
    _stage_repo(tmp_path, "bot-horde/\n")

    result = _run_setup(tmp_path, {})
    assert result.returncode == 0

    gi = (tmp_path / ".gitignore").read_text(encoding="utf-8")
    assert "local-only mode" in gi
    assert "rebuild-board workflow intentionally not installed" in gi


def test_setup_strips_stale_horde_of_bots_import_block(tmp_path):
    """An adopter who installed the previous (Horde of Bots) version has a
    stale `<!-- horde-of-bots import block -->` marker pair plus an
    `@horde-of-bots/HORDEOFBOTS.md` import in their CLAUDE.md. setup.sh must
    strip the old block in-place before adding the new bot-horde block."""
    _stage_repo(tmp_path, "", with_workflow=True)
    (tmp_path / "CLAUDE.md").write_text(
        "Existing project rules.\n"
        "\n"
        "<!-- horde-of-bots import block — managed by setup.sh; remove the block to disable horde-of-bots -->\n"
        "# horde-of-bots\n"
        "@horde-of-bots/HORDEOFBOTS.md\n"
        "<!-- /horde-of-bots import block -->\n"
        "\n"
        "More project rules.\n",
        encoding="utf-8",
    )

    result = _run_setup(tmp_path, {})
    assert result.returncode == 0, \
        f"setup.sh failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"

    claude_md = (tmp_path / "CLAUDE.md").read_text(encoding="utf-8")
    # Stale markers and stale import gone
    assert "horde-of-bots import block" not in claude_md, \
        "stale Horde-of-Bots marker survived the upgrade"
    assert "@horde-of-bots/HORDEOFBOTS.md" not in claude_md, \
        "stale Horde-of-Bots import line survived the upgrade"
    # New block in place
    assert "<!-- bot-horde import block" in claude_md
    assert "@bot-horde/BOTHORDE.md" in claude_md
    # Surrounding content preserved
    assert "Existing project rules." in claude_md
    assert "More project rules." in claude_md


def test_local_only_mode_detection_ignores_unrelated_lines(tmp_path):
    """A .gitignore that mentions horde-of-bots in a comment or a partial-match
    pattern (e.g. horde-of-bots-output/, foo/bot-horde/) must NOT trigger
    local-only mode. Pre-create the workflow so download() skips network."""
    _stage_repo(
        tmp_path,
        "# horde-of-bots notes\nhorde-of-bots-output/\nfoo/bot-horde/\n",
        with_workflow=True,
    )

    result = _run_setup(tmp_path, {})

    assert result.returncode == 0, \
        f"setup.sh failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert "local-only mode detected" not in result.stdout, \
        "false positive: .gitignore did not contain a true bot-horde/ ignore rule"
    assert (tmp_path / WORKFLOW_REL).exists(), "git-sync mode should keep the workflow"
