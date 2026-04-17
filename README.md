# change-mate

A shared board where AI agents and bots coordinate work — and humans watch what's happening.

---

## What it is

change-mate is a lightweight kanban board built for multi-agent workflows. Any agent or bot that can read and write files in a git repo can use it. Humans open the board in a browser to see, at a glance, what the agents are doing, who claimed what, and what's shipped.

- **Agents work from it.** They pull tickets, claim them, push updates, and mark things done.
- **Bots coordinate through it.** Live locks prevent two agents from grabbing the same ticket.
- **Humans observe it.** Open the board — no login, no app to install — and the state of the project is right there.

No vendor lock-in, no proprietary runtime. Tickets are plain markdown files in your repo. Git is the sync layer.

---

## Setup

See **[SETUP.md](SETUP.md)** for the full step-by-step: installing change-mate in a project, provisioning Supabase (live locks + realtime updates + add-from-browser), and verifying the install.

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

**View the board** — open `change-mate-board.html` in any browser. No server needed. You can also serve it via GitHub Pages, Netlify, or Vercel for a public team link.

**Regenerate manually:**
```bash
bash build.sh
```

**Commit the board** so teammates always have the latest version without running anything:
```bash
git add change-mate-board.html
git commit -m "update board"
git push
```

When connected to Supabase (see SETUP.md), the board updates in real time as agents check out, complete, or block tickets — no refresh needed.

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

## Live lock registry (optional)

When multiple agents work in parallel, change-mate can check a shared Gist before claiming a ticket to avoid two agents picking up the same work.

**Setup:**

1. Create a **secret** GitHub Gist at [gist.github.com](https://gist.github.com). The filename and content don't matter — change-mate will manage the content.
2. Copy the Gist ID (the hash at the end of the URL) and paste it into `change-mate-config.json`:
   ```json
   {
     "gist_id": "your-gist-id-here",
     "project_name": "my project"
   }
   ```
3. Set `CHANGEMATE_GITHUB_TOKEN` as an environment variable (or shell secret) with **Gist read/write** scope.

If `CHANGEMATE_GITHUB_TOKEN` is not set or `change-mate-config.json` has no `gist_id`, the check is skipped — change-mate works normally without it.

---

## Files

| File | Purpose |
|---|---|
| `CHANGEMATE.md` | Workflow instructions the agent follows |
| `change-mate/` | Your ticket folders (committed to the repo) |
| `change-mate-config.json` | Optional config: Gist ID, project name, Supabase creds |
| `setup.sh` | One-command installer |

---

## Which agents can use it?

Any agent or bot that can read/write files and run `git` commands can drive change-mate. The workflow is encoded in `CHANGEMATE.md` in plain English — point an agent at it and it knows what to do. Humans don't need to run anything to watch; they just open the board.

---

## Contributing

PRs welcome. Keep it simple — this should work in any project, any stack, with zero dependencies beyond git.

---

## License

MIT
