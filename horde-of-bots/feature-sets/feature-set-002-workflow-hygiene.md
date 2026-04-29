# [feature-set-002] Workflow Hygiene

## Goal
Reshape the change-mate ticket workflow so the agent operates as a senior technical PM, ticket structure carries explicit success/failure signals, tickets can reference each other, and ticket drafts can optionally pass through a critic.

## Rationale
Tickets created by the LLM today follow a thin format and a developer-voice persona, with no way to express relationships between work items. HB-003, HB-004, and HB-010 collectively address all three: relationship fields (HB-003), PM persona + new sections + product-manager skill (HB-004), and second-LLM critic on drafts (HB-010). Bundling keeps the ticket-format changes coherent and avoids two formats coexisting mid-rollout.

## Tickets
- HB-003 — Ticket relationships (related / blocks / blocked-by)
- HB-004 — Reframe CHANGEMATE.md persona + product-manager skill
- HB-010 — Second-LLM review pass on ticket drafts

## Status
In progress
