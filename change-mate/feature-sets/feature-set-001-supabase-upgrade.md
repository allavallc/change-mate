# [feature-set-001] Supabase Upgrade

## Goal
Replace the Gist-based locking and per-user GitHub PAT setup with a Supabase-backed multi-user, access-controlled, live ticket board.

## Rationale
The current setup uses a fragile GitHub Gist for locking, has zero history of ticket transitions, and requires every user to bring their own GitHub PAT for the Add Story button. CM-005 through CM-009 together replace that surface — schema, server-side write path, board access modes, agent locking via Supabase, and setup docs — into one coherent architectural cut. Bundling them prevents partial migrations that leave the system in two states at once.

## Tickets
- CM-005 — Supabase schema (locks, ticket_events, write_keys + RLS)
- CM-006 — Supabase Edge Function cm-write
- CM-007 — Board modes + write-key prompt + Add Story via Edge Function
- CM-008 — Migrate agent locking + event logging from Gist to Supabase
- CM-009 — Setup docs for new Supabase-backed architecture
- CM-012 — Show active agent/assignee on board cards via live locks

## Status
Done — 2026-04-16

## Outcome
Shipped. Auth model was simplified mid-flight: write-keys were replaced with GitHub-token verification (commit `2af97b4`), collapsing CM-007's three-mode design into a single flow where board visibility follows the repo's visibility. See each ticket's Resolution section for per-ticket detail.
