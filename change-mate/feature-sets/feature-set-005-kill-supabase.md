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
In progress
