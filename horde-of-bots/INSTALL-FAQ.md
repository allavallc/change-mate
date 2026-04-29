# change-mate — install FAQ

Quick answers to the questions adopters ask before / after running `setup.sh`. Read this once after install and you're caught up.

If a question isn't here, ask the maintainers — and tell us, so we can add it.

---

## CLAUDE.md import

**What does the import block do?**
`setup.sh` appends an `@change-mate/CHANGEMATE.md` reference to your `CLAUDE.md`. Claude Code loads that file into every session so the agent knows the change-mate workflow.

**What will the agent do autonomously?**
After you confirm a ticket draft (PM skill flow) or pick a ticket from the backlog, the agent will move the file between `change-mate/` folders and `git add / commit / push` the move. It does **not** create tickets, change ticket bodies, or move tickets without your explicit confirmation. If you have stricter rules ("no autonomous git push"), state them in your own CLAUDE.md — the agent reads CLAUDE.md top-down so your rules override change-mate's defaults.

**Can I scope the import so it only loads when I invoke the PM skill?**
No. Claude Code `@-imports` are loaded ambiently. If you want a smaller surface area: don't append the import, and invoke `/product-manager` manually when you want to draft a ticket. The board still works without the import — only the agent-driven workflow needs it.

**The block is wrapped in `<!-- change-mate import block -->` markers.** Don't edit inside the markers; setup.sh manages that block. To disable change-mate, remove the entire block (markers and all).

---

## Public-repo ticket exposure

**Are my tickets public?**
If your repo is public, yes — `change-mate/*.md` files are world-readable on GitHub. There is no in-repo encryption.

**Three workarounds:**
1. **Use a private repo** for tickets. Board still works on a private repo (with GitHub Pro for private Pages, or by opening `board.html` locally).
2. **Sanitize ticket bodies** before commit. Don't put internal infra detail (env var names, internal URLs, ports) in tickets. Put it in a private notes system and reference it abstractly.
3. **Local-only mode**: add `change-mate/` to `.gitignore`. Each developer's tickets stay on their machine — collaboration is disabled, but tickets stay private.

We don't support a hybrid (public repo + private tickets in the same repo). If you need that, use a separate repo for tickets.

**Even on private repos, treat tickets as untrusted storage.** Never put credentials, API keys, passwords, tokens, PII, or internal connection strings in a ticket body. Git history persists, repos can flip from private to public, contributors can be added later, and the agent doesn't redact anything before committing. Reference secrets abstractly — "the production DB password (vault path: `<abstract>`)" — not the value itself. CHANGEMATE.md → Rules has the same rule for the agent.

---

## GitHub Pages

**Will my board be world-readable?**
If GitHub Pages is enabled on `main` / root, yes — the board auto-serves at `https://<owner>.github.io/<repo>/change-mate/board.html`. Anyone with the URL can read it. Same caveat as the tickets: public repo = public board.

**To keep the board off Pages output:**
- Set Pages source to `/docs` (or any subfolder that doesn't include `change-mate/`). The board still exists in your repo but isn't published.
- Or use a private repo + GitHub Pro for private Pages.

**Will change-mate interfere with my existing Jekyll/Pages setup?**
No. change-mate's files live under `change-mate/` and at root (`setup.sh`). If your Pages source is `/docs`, change-mate is invisible to Pages. If your Pages source is `/`, change-mate is published alongside your site at `/change-mate/`.

---

## PAT (personal access token)

**What permissions does the PAT need?**
Fine-grained PAT, **Contents: Read and write**, scoped to the change-mate repo only. That's the only scope used.

**Where is the PAT stored?**
In each viewer's browser `localStorage`, under `cm_github_token`. It is never sent to any server other than `api.github.com`. There is no telemetry.

**Can another viewer steal my PAT?**
No. `localStorage` is origin-scoped + per-browser-per-user. Two people viewing the same Pages URL each have their own private localStorage; one cannot read the other's PAT.

**Can the PAT do anything outside `change-mate/`?**
Yes — GitHub fine-grained PATs scope by repo, not by path. A PAT with Contents: Read and write on the repo can write any file in the repo. We can't restrict that further; it's a GitHub permission-model limit. Mitigation: use a separate repo for change-mate if your main repo has files you don't want exposed to that PAT.

---

## auto_commit_board

**What does it control?**
Whether the GitHub Actions workflow `git commit`s the rebuilt `change-mate/board.html` back to `main` after a push. Default: `true`.

**When would I turn it off?**
If you don't want `chore: rebuild board [skip ci]` commits in your `git log`. Set `"auto_commit_board": false` in `change-mate/config.json`. Trade-off: your Pages-hosted board goes stale until you rebuild manually (`bash change-mate/build.sh && git add change-mate/board.html && git commit -m "refresh board" && git push`).

**This is a workflow flag, not an agent flag.** It does *not* control whether the agent commits ticket moves — the agent always commits after you confirm a move.

---

## Polling and rate limits

**How often does the board poll GitHub?**
Every 30 seconds by default. Override via `change-mate/config.json` `poll_seconds` (minimum 10).

**Authenticated or anonymous?**
If your PAT is in localStorage (you've used + Add story), polling uses that PAT. GitHub's rate limit for authenticated requests is 5000/hr per user — plenty.

If no PAT, polling is anonymous. GitHub's anonymous limit is 60/hr per IP. Multiple viewers behind one egress IP (e.g., an office) can hit this.

**What happens at the limit?**
Polling auto-disables after 5 consecutive failures. The board stops updating but stays viewable. Reload the page to resume.

---

## Skill upgrade

**Where is the PM skill installed?**
`~/.claude/skills/product-manager/SKILL.md`. Global to your machine, shared across every change-mate project.

**How do I upgrade?**
Re-run `bash setup.sh`. If a newer version is upstream, you'll be prompted to overwrite. To skip the prompt: `CHANGEMATE_UPGRADE_SKILL=yes bash setup.sh`. To upgrade non-interactively: same env var + `< /dev/null`.

**Why global, not per-project?**
That's how Claude Code's skill system works. We don't have a per-project loader.

---

## How do I know if I need to update?

`change-mate/MANIFEST.json` lists every file change-mate manages, with a version date per file. Your local copy is what setup.sh installed. The upstream copy at `https://raw.githubusercontent.com/allavallc/change-mate/main/change-mate/MANIFEST.json` always reflects the current canonical versions.

**Bot-friendly check** — fetch the upstream manifest and diff against your local copy:
```bash
CHANGEMATE_CHECK_UPDATES=yes bash <(curl -fsSL https://raw.githubusercontent.com/allavallc/change-mate/main/setup.sh)
```
Lists stale files. Exits non-zero if anything is stale (CI-friendly).

**Upgrade in place** — fetches every stale file and updates your local manifest:
```bash
CHANGEMATE_UPGRADE_DOCS=yes bash <(curl -fsSL https://raw.githubusercontent.com/allavallc/change-mate/main/setup.sh)
```

Both modes use Python 3 to parse JSON. Both are idempotent — running with no stale files is a no-op. Adopters who don't have a local manifest yet (installed before this mechanism existed) can run upgrade once to bootstrap; it treats every tracked file as needing install and writes the manifest at the end.

---

## Idempotency

**Is `bash setup.sh` safe to re-run?**
Yes. Every file write checks for existence first; markers, ignore-file appends, and the CLAUDE.md import all use exact-match presence checks. Running setup.sh ten times produces the same result as running it once.

**What if I want to force a fresh install?**
Delete `change-mate/CHANGEMATE.md` (or any file you want re-fetched) and re-run setup.sh.

---

## Non-interactive install

**Can I run `curl … | bash`?**
Yes, with one caveat: if your repo has the *legacy* layout (root-level `CHANGEMATE.md`, `build.sh`, etc.), the migration prompt needs a TTY. Without one, setup.sh detects no TTY and skips the migration with a log line. To migrate non-interactively: `CHANGEMATE_AUTO_MIGRATE=yes`.

**For CI use:**
```bash
curl -fsSL https://raw.githubusercontent.com/allavallc/change-mate/main/setup.sh | CHANGEMATE_AUTO_MIGRATE=yes CHANGEMATE_UPGRADE_SKILL=yes bash
```

---

## Python requirement

**Does change-mate need Python?**
Yes — `change-mate/build.sh` uses Python 3 to parse tickets and render the board. Any of `py`, `python3`, or `python` (with version 3.x) works. The board itself runs in a browser; only the build step needs Python.

**You don't need Python on your local machine if** you rely on GitHub Actions to rebuild the board on push. The workflow runs Python in CI.

---

## Where to ask

- Bugs: open an issue on https://github.com/allavallc/change-mate
- Feature requests: same place, label `feature`
- Quick questions: ask in the issue tracker, label `question`
