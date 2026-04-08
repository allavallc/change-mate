# change-mate

A Claude Code workflow for tracking changes like Jira tickets — without leaving your terminal.

---

## What it does

change-mate gives Claude Code a structured way to:

- Present your backlog at the start of each session
- Turn vague tasks into defined tickets before touching code
- Log every completed change with decisions and notes
- Keep a running `change-mate.md` file you can export to Jira or Trello later

---

## Setup

Inside a Claude Code session, just say:

```
I want to use change-mate. Set it up from https://github.com/allavallc/change-mate
```

Claude Code will run the setup automatically.

Or run it manually:

```bash
curl -fsSL https://raw.githubusercontent.com/allavallc/change-mate/main/setup.sh | bash
```

That's it. Setup will:

- Add `CHANGEMATE.md` to your project (the workflow instructions)
- Create `change-mate.md` (your running change log)
- Add one line to your `CLAUDE.md` to wire it all together

Your existing `CLAUDE.md` is safe — change-mate only appends a single import line.

---

## The workflow

**Start of session**
```
Claude: What are we working on?

  Open:
    A. [CM-003] Add user authentication
    B. [CM-005] Fix pagination bug

  In Progress:
    → [CM-002] Refactor data layer
```

**Pick a task**
```
You: Let's do A

Claude: Let's write this up as a ticket. Answer using the numbers:

  1. What is the goal?
  2. Why does this matter?
  3. What does done look like?
  4. Any technical notes or dependencies?
  5. Priority: Low / Medium / High / Critical
  6. Effort: XS / S / M / L / XL
```

**Answer and confirm**
```
You: 1. Add login with email and password
     2. Users can't save anything without an account
     3. User can register, log in, log out, reset password
     4. Using existing auth library, no OAuth for now
     5. High
     6. M

Claude: [CM-003] Add user authentication
        ───────────────────────────────
        Goal:      Add login with email and password
        Why:       Users can't save anything without an account
        Done when: - User can register
                   - User can log in / log out
                   - Password reset works
        Priority:  High
        Effort:    M
        Notes:     Using existing auth library, no OAuth for now

        Does this look right? (yes / edit N)
```

**After the work is done**
```
Claude: Done. I've tracked [CM-003] in change-mate.md.
```

---

## The change log

`change-mate.md` is a plain markdown file in your project root. It stays with your code, is readable by anyone, and is structured for easy export.

Example:

```markdown
### [CM-003] Add user authentication
- **Status**: done
- **Priority**: High
- **Effort**: M
- **Goal**: Add login with email and password
- **Done when**:
  - User can register
  - User can log in / log out
  - Password reset works
- **Notes**: Went with JWT over sessions for stateless API compatibility
- **Date**: 2025-01-14
```

---

## Exporting to Jira or Trello

The ticket format is designed to map cleanly to both:

| change-mate | Jira | Trello |
|---|---|---|
| CM-XXX | Issue key | Card |
| Goal | Summary | Card title |
| Why | Description | Card description |
| Done when | Acceptance criteria | Checklist |
| Priority | Priority | Label |
| Effort | Story points | Label |
| Notes | Comments | Card description |

Manual export for now — automated export coming soon.

---

## Files

| File | Purpose |
|---|---|
| `CHANGEMATE.md` | Workflow instructions loaded by Claude Code |
| `change-mate.md` | Your running change log |
| `setup.sh` | One-command installer |

---

## Contributing

PRs welcome. Keep it simple — this should work in any project, any stack, with zero dependencies.

---

## License

MIT
