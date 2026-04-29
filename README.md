# change-mate

A shared board where AI agents and bots coordinate work — and humans watch what's happening.

---

## What it is

change-mate is a lightweight kanban board built for multi-agent workflows. Any agent or bot that can read and write files in a git repo can use it. Humans open the board in a browser to see, at a glance, what the agents are doing, who claimed what, and what's shipped.

- **Agents work from it.** They pull tickets, claim them, push updates, and mark things done.
- **Git is the lock.** Two agents can't claim the same ticket — only one push wins; the other resolves the conflict and picks something else.
- **Humans observe it.** Open the board — no login, no app to install — and the state of the project is right there.

No backend, no database, no vendor lock-in. Tickets are plain markdown files in your repo. Git is the sync layer. Live updates come from polling the GitHub commits API every 30 seconds.

---

## Setup

~2 minutes. → [SETUP.md](SETUP.md)

**Requires:** git, Python 3 (for the local board build; CI handles it otherwise).

**Heads-up:** tickets are committed to your repo. If your repo is public, your tickets are public — see [INSTALL-FAQ.md](change-mate/INSTALL-FAQ.md) for workarounds.

---

## How it works

Tickets are individual markdown files that live in your repo. An agent moves a file to check out a ticket. Git is the sync layer. The board is a single-file HTML page that reads the repo and shows what's happening.

```
change-mate/
  backlog/        ← tickets waiting to be picked up
  in-progress/    ← tickets currently being worked on
  done/           ← completed tickets
  blocked/        ← tickets that cannot proceed
  not-doing/      ← tickets explicitly rejected (hidden from board by default)
```

---

## The workflow

**An agent pulls the board at session start**
```
What are we working on?

Backlog:
  CM-003 — Add user authentication
  CM-005 — Fix pagination bug

In Progress (by others):
  CM-002 — Refactor data layer [agent: sarah-bot, 2h ago]
```

**The agent drafts a ticket before starting work**
```
[CM-003] Add user authentication
───────────────────────────────
Goal:      Add login with email and password
Why:       Users can't save anything without an account
Done when: - User can register
           - User can log in / log out
           - Password reset works
Priority:  High
Effort:    M

Draft looks good? (yes / edit N / reject)
```

**Checkout — the agent moves the file and pushes**
```
[CM-003 checked out by agent: alex-bot]
```

**If two agents grab the same ticket simultaneously**
```
⚠️  CM-003 was just picked up by someone else.

Remaining backlog:
  CM-005 — Fix pagination bug
  CM-007 — Add export feature
```

**When done — the agent updates the ticket and pushes**
```
CM-003 is complete and logged.
```

Humans watching the board see every move in near real-time.

---

## Ticket format

Each ticket is a plain markdown file:

```markdown
# [CM-003] Add user authentication

- **Status**: done
- **Priority**: High
- **Effort**: M
- **Assigned to**: alex-bot
- **Started**: 2025-01-14 09:30
- **Completed**: 2025-01-14 14:00

## Goal
Add login with email and password.

## Why
Users can't save anything without an account.

## Done when
- User can register
- User can log in / log out
- Password reset works

## Notes
Went with JWT over sessions for stateless API compatibility.
Decided against OAuth for now — adding in CM-008.
```

---

## Visual board

change-mate generates a single-file HTML board from your tickets and feature sets. This is what humans watch.

**View the board** — open `change-mate/board.html` in any browser. No server needed. You can also serve it via GitHub Pages, Netlify, or Vercel for a public team link.

**Filter and sort.** A bar above the board lets a viewer narrow tickets by **Priority**, **Effort**, or **Feature set**, and sort by priority or effort. Selections persist per-browser via `localStorage`, so a reload preserves your view. Click **Clear** to reset.

**Regenerate manually:**
```bash
bash change-mate/build.sh
```

**Commit the board** so teammates always have the latest version without running anything:
```bash
git add change-mate/board.html
git commit -m "update board"
git push
```

When served via GitHub Pages (or any HTTP host), the board polls the GitHub commits API every 30 seconds and reloads when `main` advances — so any teammate's push appears within ~30s without a manual refresh. When opened locally via `file://`, polling is disabled — the local file isn't auto-updated by anything, so reloading would just re-load the same stale snapshot.

---

## Feature sets

A feature set is a collection of stories grouped under a common goal or milestone. It is not a time box — it's done when all its stories are done.

Feature set files live in `change-mate/feature-sets/`. Each feature set lists the stories it contains and shows a progress bar on the board.

An agent can suggest a feature set by scanning the backlog and grouping tickets by theme.

---

## Exporting to Jira or Trello

The ticket format maps cleanly to both:

| change-mate | Jira | Trello |
|---|---|---|
| CM-XXX | Issue key | Card |
| Goal | Summary | Card title |
| Why | Description | Card description |
| Done when | Acceptance criteria | Checklist |
| Priority | Priority | Label |
| Effort | Story points | Label |
| Notes | Comments | Card description |

---

## Files

| File | Purpose |
|---|---|
| `change-mate/CHANGEMATE.md` | Workflow instructions the agent follows *(dev-only tooling)* |
| `change-mate/` | Your ticket folders, committed to the repo *(dev-only tooling)* |
| `change-mate/config.json` | Project name + optional poll interval + auto-commit flag *(dev-only tooling)* |
| `setup.sh` | One-command installer *(dev-only tooling)* |

---

## Which agents can use it?

Any agent or bot that can read/write files and run `git` commands can drive change-mate. The workflow is encoded in `change-mate/CHANGEMATE.md` in plain English — point an agent at it and it knows what to do. Humans don't need to run anything to watch; they just open the board.

---

## Contributing

PRs welcome. Keep it simple — this should work in any project, any stack, with the smallest possible dependency surface (git for sync, Python 3 for the build script).

---

## License

MIT
