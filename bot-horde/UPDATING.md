# How to update Horde of Bots

This is the canonical update procedure for both bots and humans. This file is referenced from `bot-horde/BOTHORDE.md` and from `bot-horde/INSTALL-FAQ.md`.

## Quick reference

**Check** (read-only — safe to run any time, including from CI):

```bash
HORDEOFBOTS_CHECK_UPDATES=yes bash <(curl -fsSL https://raw.githubusercontent.com/allavallc/bot-horde/main/setup.sh)
```

- **Exit code 0** → up to date. Nothing to do.
- **Exit code 1** → at least one file is stale. The stdout lists each stale file with its local and upstream versions.

**Upgrade** (writes — re-fetches every stale file and updates the local `MANIFEST.json`):

```bash
HORDEOFBOTS_UPGRADE_DOCS=yes bash <(curl -fsSL https://raw.githubusercontent.com/allavallc/bot-horde/main/setup.sh)
```

**After upgrade** — commit the result:

```bash
git add bot-horde/ .github/workflows/bot-horde-rebuild-board.yml
git commit -m "chore: update Horde of Bots"
git push
```

## How the manifest works

`bot-horde/MANIFEST.json` lists every file Horde of Bots manages and the version of each. The "version" is an ISO date for docs/scripts and a semver string for the PM skill. Local copy reflects what `setup.sh` last installed; the upstream copy at `https://raw.githubusercontent.com/allavallc/bot-horde/main/bot-horde/MANIFEST.json` always reflects the current canonical versions.

`HORDEOFBOTS_CHECK_UPDATES=yes` fetches the upstream manifest, parses both with Python 3, and prints any file whose version differs.

`HORDEOFBOTS_UPGRADE_DOCS=yes` does the same diff and re-fetches every stale file, then writes the upstream manifest as the new local manifest.

## What gets fetched on upgrade

The list lives in `bot-horde/MANIFEST.json` under `files`. As of this writing:

- `bot-horde/BOTHORDE.md`
- `bot-horde/INSTALL-FAQ.md`
- `bot-horde/UPDATING.md` (this file)
- `bot-horde/MANIFEST.json`
- `bot-horde/build.sh`
- `bot-horde/build_lib.py`
- `bot-horde/config.json`
- `.github/workflows/bot-horde-rebuild-board.yml`
- `skills/product-manager/SKILL.md` (the global PM skill)

## Bots: read this carefully

- **Run the check freely.** It's a network read-only call; no risk.
- **Do not auto-upgrade.** Surface stale files to the user and ask first. Upgrade overwrites local edits to managed files.
- If the user approves, run the upgrade command, then commit + push the result. The agent's normal "no-secrets-in-commit-messages" rule still applies.
- For CI / non-interactive runs, the upgrade command honors `HORDEOFBOTS_AUTO_MIGRATE=yes` and `HORDEOFBOTS_UPGRADE_SKILL=yes` to skip prompts that would otherwise hang.

## Edge cases

- **No local manifest** (existing adopters from before the manifest existed): upgrade mode treats every tracked file as stale and bootstraps cleanly. Re-run after to confirm exit-code-0.
- **Upstream unreachable** (offline / rate-limited): both modes exit 2 with a clear error. Try again later.
- **Partial fetch failure**: if any file fails mid-upgrade, the local manifest is left untouched so the next check still shows everything as stale.
- **Local edits to managed files**: the upgrade overwrites them. If you must edit a managed file, fork it under a different name and reference that.
- **Local-only mode** (`bot-horde/` is in `.gitignore`): both check and upgrade skip `.github/workflows/bot-horde-rebuild-board.yml` — it would fail in CI since `build.sh` isn't tracked. The workflow itself is also self-defending: if installed but `bot-horde/build.sh` is absent at run time, it short-circuits with a notice instead of failing.
