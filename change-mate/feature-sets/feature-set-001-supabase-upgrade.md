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

## Status
Planned
