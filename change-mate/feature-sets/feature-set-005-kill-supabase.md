# [feature-set-005] Kill Supabase

## Goal
Eliminate Supabase as a dependency. Replace Realtime with GitHub commit polling, replace cm-write with browser-direct Contents API calls, then delete the entire Supabase folder + docs + tests.

## Rationale
Supabase was added in feature-set-001 to give the board live updates and a server-side ticket-ID claim. In practice the project pauses after a week of inactivity, the migrations are fragile across pause-restore cycles, and the cost (Edge Function deploy, CLI install, three SQL migrations, two API keys) far outweighs the benefit (30-second freshness vs. live updates). Git is already the source of truth; the browser already has the user's GitHub PAT. Removing the backend simplifies setup from ~15 minutes to ~30 seconds and eliminates the project-paused failure mode entirely.

## Tickets
- CM-057 — Replace Supabase Realtime with GitHub commit polling
- CM-058 — Add Story → direct GitHub Contents API (drop cm-write)
- CM-059 — Delete Supabase footprint and simplify setup

## Status
Done — 2026-04-27

## Outcome
Shipped. The board now runs entirely on git + GitHub Pages + the user's existing fine-grained PAT. No backend, no database, no migrations, no deploy CLI, no project that pauses. Live updates come from polling `GET /repos/{owner}/{repo}/commits/main` every 30s (configurable via `change-mate/config.json` `poll_seconds`, min 10s); on HEAD SHA change the page reloads. Add Story PUTs directly to the GitHub Contents API with the user's PAT (retries up to 5x on 422 conflicts). Locks are implicit — git push is the lock; conflicting pushes resolve at the git layer. SETUP.md fits on one screen.
