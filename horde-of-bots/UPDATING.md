# How to update change-mate

This is the canonical update procedure for both bots and humans. This file is referenced from `change-mate/CHANGEMATE.md` and from `change-mate/INSTALL-FAQ.md`.

## Quick reference

**Check** (read-only — safe to run any time, including from CI):

```bash
CHANGEMATE_CHECK_UPDATES=yes bash <(curl -fsSL https://raw.githubusercontent.com/allavallc/change-mate/main/setup.sh)
```

- **Exit code 0** → up to date. Nothing to do.
- **Exit code 1** → at least one file is stale. The stdout lists each stale file with its local and upstream versions.

**Upgrade** (writes — re-fetches every stale file and updates the local `MANIFEST.json`):

```bash
CHANGEMATE_UPGRADE_DOCS=yes bash <(curl -fsSL https://raw.githubusercontent.com/allavallc/change-mate/main/setup.sh)
```

**After upgrade** — commit the result:

```bash
git add change-mate/ .github/workflows/change-mate-rebuild-board.yml
git commit -m "chore: update change-mate"
git push
```

## How the manifest works

`change-mate/MANIFEST.json` lists every file change-mate manages and the version of each. The "version" is an ISO date for docs/scripts and a semver string for the PM skill. Local copy reflects what `setup.sh` last installed; the upstream copy at `https://raw.githubusercontent.com/allavallc/change-mate/main/change-mate/MANIFEST.json` always reflects the current canonical versions.

`CHANGEMATE_CHECK_UPDATES=yes` fetches the upstream manifest, parses both with Python 3, and prints any file whose version differs.

`CHANGEMATE_UPGRADE_DOCS=yes` does the same diff and re-fetches every stale file, then writes the upstream manifest as the new local manifest.

## What gets fetched on upgrade

The list lives in `change-mate/MANIFEST.json` under `files`. As of this writing:

- `change-mate/CHANGEMATE.md`
- `change-mate/INSTALL-FAQ.md`
- `change-mate/UPDATING.md` (this file)
- `change-mate/MANIFEST.json`
- `change-mate/build.sh`
- `change-mate/build_lib.py`
- `change-mate/config.json`
- `.github/workflows/change-mate-rebuild-board.yml`
- `skills/product-manager/SKILL.md` (the global PM skill)

## Bots: read this carefully

- **Run the check freely.** It's a network read-only call; no risk.
- **Do not auto-upgrade.** Surface stale files to the user and ask first. Upgrade overwrites local edits to managed files.
- If the user approves, run the upgrade command, then commit + push the result. The agent's normal "no-secrets-in-commit-messages" rule still applies.
- For CI / non-interactive runs, the upgrade command honors `CHANGEMATE_AUTO_MIGRATE=yes` and `CHANGEMATE_UPGRADE_SKILL=yes` to skip prompts that would otherwise hang.

## Edge cases

- **No local manifest** (existing adopters from before the manifest existed): upgrade mode treats every tracked file as stale and bootstraps cleanly. Re-run after to confirm exit-code-0.
- **Upstream unreachable** (offline / rate-limited): both modes exit 2 with a clear error. Try again later.
- **Partial fetch failure**: if any file fails mid-upgrade, the local manifest is left untouched so the next check still shows everything as stale.
- **Local edits to managed files**: the upgrade overwrites them. If you must edit a managed file, fork it under a different name and reference that.
- **Local-only mode** (`change-mate/` is in `.gitignore`): both check and upgrade skip `.github/workflows/change-mate-rebuild-board.yml` — it would fail in CI since `build.sh` isn't tracked. The workflow itself is also self-defending: if installed but `change-mate/build.sh` is absent at run time, it short-circuits with a notice instead of failing.
