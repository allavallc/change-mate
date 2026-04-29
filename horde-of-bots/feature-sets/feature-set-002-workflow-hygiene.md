# [feature-set-002] Workflow Hygiene

## Goal
Reshape the change-mate ticket workflow so the agent operates as a senior technical PM, ticket structure carries explicit success/failure signals, tickets can reference each other, and ticket drafts can optionally pass through a critic.

## Rationale
Tickets created by the LLM today follow a thin format and a developer-voice persona, with no way to express relationships between work items. CM-003, CM-004, and CM-010 collectively address all three: relationship fields (CM-003), PM persona + new sections + product-manager skill (CM-004), and second-LLM critic on drafts (CM-010). Bundling keeps the ticket-format changes coherent and avoids two formats coexisting mid-rollout.

## Tickets
- CM-003 — Ticket relationships (related / blocks / blocked-by)
- CM-004 — Reframe CHANGEMATE.md persona + product-manager skill
- CM-010 — Second-LLM review pass on ticket drafts

## Status
In progress
