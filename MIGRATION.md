# Migrating to Bot Horde

The project formerly known as **Horde of Bots** is now **Bot Horde**. Tickets use the `BH-` prefix instead of `HB-`. The install command, ticket format, board UI, and workflow are unchanged — only names changed. This note tells your bot (or you) how to migrate an existing repo.

> **Coming from `change-mate`?** That earlier name → Horde of Bots rename happened in the previous release. The script below handles both transitions in one shot — `change-mate/` and `horde-of-bots/` directories both end up at `bot-horde/`, `CM-*` and `HB-*` ticket files both become `BH-*`. You only need to migrate once.

The repo URL `github.com/allavallc/horde-of-bots` (and the older `github.com/allavallc/change-mate`) auto-redirects to `github.com/allavallc/bot-horde`, so existing clones still pull and push. Update remotes when convenient.

## What changed in this rename

| Before (Horde of Bots) | After (Bot Horde) |
|---|---|
| `horde-of-bots/` directory | `bot-horde/` |
| `HORDEOFBOTS.md` | `BOTHORDE.md` |
| `HB-NNN` ticket IDs | `BH-NNN` (numbers preserved) |
| `.github/workflows/horde-of-bots-rebuild-board.yml` | `bot-horde-rebuild-board.yml` |
| `HORDEOFBOTS_*` env vars (UPGRADE_DOCS, REMOVE_WORKFLOW, AUTO_MIGRATE, etc.) | `BOTHORDE_*` |
| HTML/CSS IDs `hb-*` (poll, robot, live-indicator, etc.) | `bh-*` |
| `localStorage` keys `hb_*` (board filters, GitHub PAT cache, agent name) | `bh_*` (one-time re-auth in browser) |
| CLAUDE.md import block markers `<!-- horde-of-bots import block ... -->` | `<!-- bot-horde import block ... -->` |

## What didn't change

- `bash setup.sh` install flow
- Ticket markdown format (sections, frontmatter, all unchanged)
- The board UI, brutalist styling, walking robots, filter/sort, stale-claim render, validator
- Anything about how agents read or write tickets

## Migration — one-shot bash

Run from your repo root. Safe to re-run; idempotent. Handles either predecessor (`change-mate` or `horde-of-bots`).

```bash
set -e

# 1. Rename directory + managed filenames (handles both predecessors)
[ -d horde-of-bots ] && git mv horde-of-bots bot-horde
[ -d change-mate ] && git mv change-mate bot-horde
[ -f bot-horde/HORDEOFBOTS.md ] && git mv bot-horde/HORDEOFBOTS.md bot-horde/BOTHORDE.md
[ -f bot-horde/CHANGEMATE.md ] && git mv bot-horde/CHANGEMATE.md bot-horde/BOTHORDE.md
[ -f .github/workflows/horde-of-bots-rebuild-board.yml ] && \
  git mv .github/workflows/horde-of-bots-rebuild-board.yml .github/workflows/bot-horde-rebuild-board.yml
[ -f .github/workflows/change-mate-rebuild-board.yml ] && \
  git mv .github/workflows/change-mate-rebuild-board.yml .github/workflows/bot-horde-rebuild-board.yml

# 2. Rename ticket files HB-NNN → BH-NNN and CM-NNN → BH-NNN (numbers preserved)
for d in backlog in-progress done blocked not-doing; do
  for prefix in HB CM; do
    for f in bot-horde/$d/${prefix}-*.md; do
      [ -f "$f" ] || continue
      git mv "$f" "$(echo "$f" | sed "s|/${prefix}-|/BH-|")"
    done
  done
done

# 3. Rewrite ticket-ID references inside every markdown file
find bot-horde -name '*.md' -exec \
  sed -i -E 's/\b(HB|CM)-([0-9]+)\b/BH-\2/g' {} +

# 4. Update CLAUDE.md import line + marker block (if present)
[ -f CLAUDE.md ] && {
  sed -i 's|@horde-of-bots/HORDEOFBOTS\.md|@bot-horde/BOTHORDE.md|g' CLAUDE.md
  sed -i 's|@change-mate/CHANGEMATE\.md|@bot-horde/BOTHORDE.md|g' CLAUDE.md
  sed -i 's|<!-- horde-of-bots import block|<!-- bot-horde import block|g' CLAUDE.md
  sed -i 's|<!-- /horde-of-bots import block|<!-- /bot-horde import block|g' CLAUDE.md
  sed -i 's|<!-- change-mate import block|<!-- bot-horde import block|g' CLAUDE.md
  sed -i 's|<!-- /change-mate import block|<!-- /bot-horde import block|g' CLAUDE.md
}

# 5. Update .gitignore (if running in local-only mode) and deploy-ignores
for f in .gitignore .dockerignore .gcloudignore .vercelignore; do
  [ -f "$f" ] && {
    sed -i 's|^horde-of-bots/\?$|bot-horde/|' "$f"
    sed -i 's|^change-mate/\?$|bot-horde/|' "$f"
  }
done

# 6. Pull the new build.sh + spec + workflow + supporting files
for f in build.sh build_lib.py validate.py config.json BOTHORDE.md INSTALL-FAQ.md UPDATING.md MANIFEST.json; do
  curl -fsSL "https://raw.githubusercontent.com/allavallc/bot-horde/main/bot-horde/$f" \
       -o "bot-horde/$f"
done
curl -fsSL "https://raw.githubusercontent.com/allavallc/bot-horde/main/.github/workflows/bot-horde-rebuild-board.yml" \
     -o ".github/workflows/bot-horde-rebuild-board.yml"

# 7. Update local git remote — GitHub auto-redirects, but cleaner this way
git remote set-url origin https://github.com/allavallc/bot-horde.git 2>/dev/null || true
```

## Verify

```bash
# No HB- or CM- ticket files remain
find . -name 'HB-[0-9]*.md' -o -name 'CM-[0-9]*.md' | head
#   (expected: empty)

# Build works (validator runs as part of build)
bash bot-horde/build.sh
#   (expected: "[validate] OK ..." then "bot-horde/board.html updated")

# Tests pass (if you have the test suite)
py -m pytest tests/ -v
#   (expected: all green)
```

## Commit + push

```bash
git add -A
git commit -m "chore: migrate to Bot Horde"
git push
```

CI rebuilds the board on push.

## After migration

- **Browser**: open the board, click "+ Add story". You'll be re-prompted for your GitHub PAT once (storage key renamed `hb_github_token` → `bh_github_token`). Saved filter state also resets once (`hb_board_filters_v1` → `bh_board_filters_v1`).
- **Custom `config.json`**: if you had customized `project_name` in `bot-horde/config.json`, step 6 above overwrote it. Re-set your value:
  ```json
  {
    "project_name": "Your Project Name",
    "ticket_prefix": "BH"
  }
  ```
- **Future renames are config-driven**: change `project_name` and `ticket_prefix` in `bot-horde/config.json` and the masthead + parser pick it up. The directory name and `BOTHORDE.md` filename are still hard-coded — accept the tradeoff or fork.

## Rollback

If something goes wrong before you push:

```bash
git reset --hard HEAD
git checkout -- .
```

If you've already pushed and need to revert: `git revert` the migration commit and force-push (coordinate with anyone else on the repo first).

## Questions

File an issue at https://github.com/allavallc/bot-horde/issues.
