# Onboarding

## Setup checklist

- [ ] Clone the repo — the Gist ID is already in `change-mate/config.json`
- [ ] Request the shared `CHANGEMATE_GITHUB_TOKEN` from whoever holds it
- [ ] Add the token to your shell:
  ```bash
  echo 'export CHANGEMATE_GITHUB_TOKEN=<token>' >> ~/.bashrc
  source ~/.bashrc
  ```
- [ ] Verify it's set: `echo $CHANGEMATE_GITHUB_TOKEN`

## How the live lock registry works

When you claim a ticket, change-mate writes a lock entry to a shared GitHub Gist. This prevents two agents from picking up the same ticket at the same time. The lock is released automatically when the ticket is marked done.

The registry is **best-effort** — if the Gist is unreachable, work proceeds without locking and a warning is logged.

Requirements: `change-mate/config.json` must have a `gist_id` and `CHANGEMATE_GITHUB_TOKEN` must be set.

---

For the full workflow, see [CHANGEMATE.md](../../change-mate/CHANGEMATE.md).
