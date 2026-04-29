# Migrating from change-mate to Horde of Bots

The project formerly known as `change-mate` is now **Horde of Bots**. Tickets use the `HB-` prefix instead of `CM-`. The install command, ticket format, board UI, and workflow are unchanged — only names changed. This note tells your bot (or you) how to migrate an existing repo.

The repo URL `github.com/allavallc/change-mate` auto-redirects to `github.com/allavallc/horde-of-bots`, so existing clones still pull and push. Update remotes when convenient.

## What changed

| Before | After |
|---|---|
| `change-mate/` directory | `horde-of-bots/` |
| `CHANGEMATE.md` | `HORDEOFBOTS.md` |
| `CM-NNN` ticket IDs | `HB-NNN` (numbers preserved) |
| `.github/workflows/change-mate-rebuild-board.yml` | `horde-of-bots-rebuild-board.yml` |
| `CHANGEMATE_*` env vars (UPGRADE_DOCS, REMOVE_WORKFLOW, etc.) | `HORDEOFBOTS_*` |
| `localStorage` keys (`cm_github_token`, etc.) | `hb_*` (one-time re-auth in browser) |

## What didn't change

- `bash setup.sh` install flow
- Ticket markdown format (sections, frontmatter, all unchanged)
- The board UI, brutalist styling, walking robots, filter/sort
- Anything about how agents read or write tickets

## Migration — one-shot bash

Run from your repo root. Safe to re-run; idempotent.

```bash
set -e

# 1. Rename directory + managed filenames
[ -d change-mate ] && git mv change-mate horde-of-bots
[ -f horde-of-bots/CHANGEMATE.md ] && git mv horde-of-bots/CHANGEMATE.md horde-of-bots/HORDEOFBOTS.md
[ -f .github/workflows/change-mate-rebuild-board.yml ] && \
  git mv .github/workflows/change-mate-rebuild-board.yml .github/workflows/horde-of-bots-rebuild-board.yml

# 2. Rename ticket files CM-NNN → HB-NNN (numbers preserved)
for d in backlog in-progress done blocked not-doing; do
  for f in horde-of-bots/$d/CM-*.md; do
    [ -f "$f" ] || continue
    git mv "$f" "$(echo "$f" | sed 's|/CM-|/HB-|')"
  done
done

# 3. Rewrite CM-NNN references inside every markdown file
find horde-of-bots -name '*.md' -exec \
  sed -i 's/\bCM-\([0-9][0-9]*\)\b/HB-\1/g' {} +

# 4. Update CLAUDE.md import line (if present)
[ -f CLAUDE.md ] && \
  sed -i 's|@change-mate/CHANGEMATE\.md|@horde-of-bots/HORDEOFBOTS.md|g' CLAUDE.md

# 5. Update .gitignore (if running in local-only mode) and deploy-ignores
for f in .gitignore .dockerignore .gcloudignore .vercelignore; do
  [ -f "$f" ] && sed -i 's|^change-mate/\?$|horde-of-bots/|' "$f"
done

# 6. Pull the new build.sh + spec + workflow + supporting files
for f in build.sh build_lib.py config.json HORDEOFBOTS.md INSTALL-FAQ.md UPDATING.md MANIFEST.json; do
  curl -fsSL "https://raw.githubusercontent.com/allavallc/horde-of-bots/main/horde-of-bots/$f" \
       -o "horde-of-bots/$f"
done
curl -fsSL "https://raw.githubusercontent.com/allavallc/horde-of-bots/main/.github/workflows/horde-of-bots-rebuild-board.yml" \
     -o ".github/workflows/horde-of-bots-rebuild-board.yml"

# 7. (Optional) update local git remote — GitHub auto-redirects, but cleaner this way
git remote set-url origin https://github.com/allavallc/horde-of-bots.git 2>/dev/null || true
```

## Verify

```bash
# No CM- ticket files remain
find . -name 'CM-[0-9]*.md' | head
#   (expected: empty)

# Build works
bash horde-of-bots/build.sh
#   (expected: "horde-of-bots/board.html updated")

# Tests pass (if you have the test suite)
py -m pytest tests/ -v
#   (expected: all green)
```

## Commit + push

```bash
git add -A
git commit -m "chore: migrate from change-mate to Horde of Bots"
git push
```

CI rebuilds the board on push.

## After migration

- **Browser**: open the board, click "+ Add story". You'll be re-prompted for your GitHub PAT once (storage key renamed `cm_github_token` → `hb_github_token`). Saved filter state also resets once.
- **Custom `config.json`**: if you had customized `project_name` in `horde-of-bots/config.json`, step 6 above overwrote it. Re-set your value:
  ```json
  {
    "project_name": "Your Project Name",
    "ticket_prefix": "HB"
  }
  ```
- **Future renames are now config-driven**: change `project_name` and `ticket_prefix` in `horde-of-bots/config.json` and the masthead + parser pick it up. The directory name and `HORDEOFBOTS.md` filename are still hard-coded — accept the tradeoff or fork.

## Rollback

If something goes wrong before you push:

```bash
git reset --hard HEAD
git checkout -- .
```

If you've already pushed and need to revert: `git revert` the migration commit and force-push (coordinate with anyone else on the repo first).

## Questions

File an issue at https://github.com/allavallc/horde-of-bots/issues.
