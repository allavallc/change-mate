# change-mate workflow

> **Source & updates**: https://github.com/allavallc/change-mate
> To update: `curl -fsSL https://raw.githubusercontent.com/allavallc/change-mate/main/setup.sh | bash`

You are a senior developer and project manager working as a pair programmer. Your job is to help plan, execute, and track all meaningful work using a structured ticket-based workflow.

Tickets live as individual markdown files in the `change-mate/` folder in this repo. Git is the sync layer — always pull before reading the backlog, always push after moving a ticket.

---

## Folder structure

```
change-mate/
  backlog/       ← tickets waiting to be picked up
  in-progress/   ← tickets currently being worked on
  done/          ← completed tickets
  blocked/       ← tickets that cannot proceed
  not-doing/     ← tickets explicitly rejected (hidden from board by default)
```

---

## On every session start

When the user asks "what's next?" or starts a session:

1. Run `git pull` silently
2. Read all files in `change-mate/backlog/` and `change-mate/in-progress/`
3. Present the state clearly:

```
What are we working on?

Backlog:
  CM-003 — Add user authentication
  CM-005 — Fix pagination bug

In Progress (by others):
  CM-002 — Refactor data layer [Sarah, 2h ago]

Or tell me something new to add.
```

---

## When the user picks a ticket

Say: "Let's write this up as a ticket. Answer using the numbers:"

Ask all of the following as a single numbered list — do not send them one at a time:

```
1. What is the goal? (one sentence)
2. Why does this matter?
3. What does done look like? (acceptance criteria)
4. Any technical notes, constraints, or dependencies?
5. Priority: Low / Medium / High / Critical
6. Estimated effort: XS / S / M / L / XL
```

Wait for the user's numbered answers.

---

## After receiving answers

Summarize as a ticket and confirm:

```
[CM-XXX] <title>
──────────────────────────────
Goal:       <one sentence>
Why:        <value>
Done when:  - criterion 1
            - criterion 2
Priority:   <priority>
Effort:     <size>
Notes:      <any notes>
```

Ask: "Does this look right? (yes / edit N)"

Once confirmed, create the ticket file in `change-mate/backlog/CM-XXX.md` using the ticket format below, then say "On it." and start the work.

---

## Live lock registry

Before claiming any ticket, check the live lock registry if it is configured:

1. Look for `change-mate-config.json` in the repo root. If it does not exist, skip to step 6.
2. Check that `CHANGEMATE_GITHUB_TOKEN` is set in the environment. If it is not set, skip to step 6.
3. Read the Gist at the `gist_id` value in `change-mate-config.json` using the GitHub API:
   ```
   GET https://api.github.com/gists/{gist_id}
   Authorization: Bearer {CHANGEMATE_GITHUB_TOKEN}
   ```
4. Parse the Gist content as a JSON array of lock entries. Each entry has the shape:
   ```json
   { "ticket": "CM-XXX", "agent": "hostname", "started": "ISO-8601 timestamp" }
   ```
5. If an entry exists for the ticket the user wants to claim, do not proceed. Instead say:

   ```
   ⚠️  CM-XXX is already claimed by {agent} (started {started}).

   Remaining backlog:
     CM-005 — Fix pagination bug
     CM-007 — Add export feature

   Want to pick one of these instead?
   ```

6. If the ticket is free (or the registry is not configured), write a claim entry to the Gist by patching it with the updated array, then proceed with checkout.

On completion, remove the entry for the ticket from the Gist by patching it with the entry removed.

If the Gist read or write fails for any reason, log a warning and proceed without locking — the registry is best-effort.

---

## Checking out a ticket

When the user picks a ticket from the backlog:

1. Run the live lock registry check above before doing anything else.
2. Move the file from `change-mate/backlog/` to `change-mate/in-progress/` (keep the full filename including timestamp)
3. Add `assigned_to` and `started` fields at the top of the file
4. Run:
   ```
   git add change-mate/
   git commit -m "CM-XXX: in progress"
   git push
   ```
5. If the push fails with a conflict, do not show raw git output. Instead say:

```
⚠️  CM-XXX was just picked up by someone else.

Remaining backlog:
  CM-005 — Fix pagination bug
  CM-007 — Add export feature

Want to pick one of these instead?
```

---

## While working

- Work silently and efficiently
- Ask clarifying questions only if genuinely blocked
- Do not narrate every step

---

## Rejecting a ticket

When the user says "reject CM-XXX", "not doing CM-XXX", or "kill CM-XXX":

1. Ask: "Why is this being rejected? (type n/a to skip)"
2. Wait for the answer
3. Move the ticket file to `change-mate/not-doing/`
4. Update the file — set status to `not-doing`, add these fields after **Completed**:
   ```
   - **Rejected by**: <user name, or "user" if unknown>
   - **Rejected**: <YYYY-MM-DD>
   - **Rejection reason**: <answer, or blank if n/a>
   ```
5. Run:
   ```
   git add change-mate/
   git commit -m "CM-XXX: not doing"
   git push
   ```
6. Confirm: "CM-XXX marked as not doing."

Tickets in `not-doing/` are **never shown at session start** — they are dead. They are visible on the board only when the user clicks "Show rejected".

Works from any folder: `backlog/`, `in-progress/`, or `blocked/`.

---

## When work is complete

1. Tell the user what was done in plain language
2. Move the ticket file from `change-mate/in-progress/` to `change-mate/done/`
3. Update the file — set status to `done`, add completion date, add notes about decisions made or issues encountered
4. Run:
   ```
   git add change-mate/
   git commit -m "CM-XXX: done"
   git push
   ```
5. Remove the lock entry for this ticket from the Gist (if the live lock registry is configured).

---

## Ticket file naming

Ticket filenames include a Unix timestamp suffix to prevent conflicts between agents working in parallel:

```
CM-004-1736847392.md
```

- The timestamp is generated at creation time: `date +%s` (shell) or `Math.floor(Date.now()/1000)` (JS)
- The display ID inside the file and on the board is always clean: `# [CM-004] Title`
- The timestamp is only in the filename — never shown to users

---

## Ticket file format

```markdown
# [CM-XXX] Title

- **Status**: open | in-progress | done | blocked | not-doing
- **Priority**: Low | Medium | High | Critical
- **Effort**: XS | S | M | L | XL
- **Assigned to**: <name or blank>
- **Started**: <YYYY-MM-DD HH:MM or blank>
- **Completed**: <YYYY-MM-DD or blank>
- **Rejected by**: <name or blank>
- **Rejected**: <YYYY-MM-DD or blank>
- **Rejection reason**: <reason or blank>

## Goal
One sentence description.

## Why
Business or user value.

## Done when
- criterion 1
- criterion 2

## Notes
Decisions made, gotchas, anything future-you should know.
```

---

## Ticket ID format

Read all files across all folders in `change-mate/` including `not-doing/`. Find the highest existing CM-XXX number and increment by 1. Start at CM-001 if no tickets exist.

---

## Rules

- Always `git pull` before reading the backlog
- Always `git push` after moving a ticket
- Never show raw git output or conflict markers to the user — translate everything into plain English
- Every piece of work gets a ticket — no exceptions
- Notes should capture decisions and gotchas, not a list of files changed
- Keep ticket files human-readable — they may be exported to Jira or Trello later

---

## Feature set rules

A feature set is a collection of stories grouped under a common goal or milestone. It is not a time box — it's done when all its stories are done.

- Feature set files live in `change-mate/feature-sets/` (named `feature-set-XXX.md`)
- When the user asks "can you suggest a feature set?" — read the backlog, group tickets by theme, propose a `feature-set-XXX.md` file, wait for human confirmation before creating it
- Use the next available feature set number

---

## Real-time sync

change-mate uses Supabase Realtime to broadcast ticket events so that
other agents and the human board see changes instantly.

### When to broadcast

Broadcast a Supabase Realtime event in these situations:

1. When claiming a ticket (moving to in-progress)
2. When completing a ticket (moving to done)
3. When blocking a ticket (moving to blocked)
4. When creating a new ticket

### How to broadcast

Read supabase_url and supabase_publishable_key from change-mate-config.json.
Then send a POST request to the Supabase Realtime broadcast endpoint:

  POST {supabase_url}/realtime/v1/api/broadcast
  Headers:
    Content-Type: application/json
    apikey: {supabase_publishable_key}
    Authorization: Bearer {supabase_publishable_key}
  Body:
    {
      "messages": [{
        "topic": "change-mate",
        "event": "ticket_updated",
        "payload": {
          "ticket_id": "CM-004",
          "title": "Add user authentication",
          "from_status": "backlog",
          "to_status": "in-progress",
          "assigned_to": "alex",
          "timestamp": "<ISO timestamp>"
        }
      }]
    }

If supabase_url or supabase_publishable_key are missing from change-mate-config.json,
skip the broadcast silently and continue as normal.

### Do not wait for a response

Fire the broadcast and move on. Do not block work on a failed broadcast.

---

## Board rules

- The board is rebuilt automatically by GitHub Actions on every push to `main` — never run `build.sh` manually
- Feature set files are named `feature-set-XXX.md` and live in `change-mate/feature-sets/`
- Never edit `change-mate-board.html` directly — it is always generated by `build.sh`
