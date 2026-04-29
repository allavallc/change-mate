# [feature-set-008] Board filtering

## Goal
User-side controls (filter, sort, eventually search) for slicing the board without rebuilding it.

## Rationale
Once a backlog has dozens of tickets, the bare kanban gets noisy. This set covers the lightweight client-side controls a user reaches for to focus the view. Distinct from feature-set-004-board-ux (animation, perimeter robot) and feature-set-006-redesign (visual styling) — those are fixed presentation concerns, this is dynamic user control.

## Tickets
- HB-069 — Filter and sort controls on the board (done 2026-04-29)

## Status
In progress — v1 shipped in HB-069. Future work in this set: search-by-text, filter-by-assignee, saved filter presets (each as its own ticket if pulled).
