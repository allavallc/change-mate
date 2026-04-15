# change-mate

A Claude Code workflow for tracking changes like Jira tickets — without leaving your terminal. Works for solo devs and teams.

---

## What it does

change-mate gives Claude Code a structured way to:

- Pull the latest backlog at the start of every session
- Turn vague tasks into defined tickets before touching code
- Check out tickets so teammates know what's being worked on
- Log every completed change with decisions and notes
- Keep a history that can be exported to Jira or Trello later

---

## Setup

See **[SETUP.md](SETUP.md)** for the full step-by-step: installing change-mate in a project, provisioning Supabase (live locks + history + write keys), and verifying the install.

---

## How it works

Tickets are individual markdown files that live in your repo. Moving a file is how you check out a ticket. Git is the sync layer.

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

**Start of session — Claude pulls latest and shows the board**
```
What are we working on?

Backlog:
  CM-003 — Add user authentication
  CM-005 — Fix pagination bug

In Progress (by others):
  CM-002 — Refactor data layer [Sarah, 2h ago]
```

**Pick a ticket — Claude defines it before starting**
```
You: Let's do CM-003

Claude: Let's write this up as a ticket. Answer using the numbers:

  1. What is the goal?
  2. Why does this matter?
  3. What does done look like?
  4. Any technical notes or dependencies?
  5. Priority: Low / Medium / High / Critical
  6. Effort: XS / S / M / L / XL
```

**Claude checks it out — moves the file, pushes to repo**
```
Claude: [CM-003] Add user authentication
        ───────────────────────────────
        Goal:      Add login with email and password
        Why:       Users can't save anything without an account
        Done when: - User can register
                   - User can log in / log out
                   - Password reset works
        Priority:  High
        Effort:    M

        Does this look right? (yes / edit N)

You: yes

Claude: On it. [CM-003 checked out]
```

**If two devs grab the same ticket simultaneously**
```
⚠️  CM-003 was just picked up by someone else.

Remaining backlog:
  CM-005 — Fix pagination bug
  CM-007 — Add export feature

Want to pick one of these instead?
```

**When done — Claude updates the ticket and pushes**
```
Claude: Done. CM-003 is complete and logged.
```

---

## Ticket format

Each ticket is a plain markdown file:

```markdown
# [CM-003] Add user authentication

- **Status**: done
- **Priority**: High
- **Effort**: M
- **Assigned to**: Alex
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

change-mate generates a single-file HTML board from your tickets and feature sets.

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

---

## Feature sets

A feature set is a collection of stories grouped under a common goal or milestone. It is not a time box — it's done when all its stories are done.

Feature set files live in `change-mate/feature-sets/`. Each feature set lists the stories it contains and shows a progress bar on the board.

To suggest a feature set, just say: "can you suggest a feature set?" — Claude will read your backlog, group tickets by theme, and propose one for your review.

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
| `CHANGEMATE.md` | Workflow instructions loaded by Claude Code |
| `change-mate/` | Your ticket folders (committed to the repo) |
| `change-mate-config.json` | Optional config: Gist ID and project name |
| `setup.sh` | One-command installer |

---

## Contributing

PRs welcome. Keep it simple — this should work in any project, any stack, with zero dependencies beyond git.

---

## License

MIT
