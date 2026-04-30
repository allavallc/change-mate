# [feature-set-002] Workflow Hygiene

## Goal
Reshape the Horde of Bots ticket workflow so the agent operates as a senior technical PM, ticket structure carries explicit success/failure signals, tickets can reference each other, and ticket drafts can optionally pass through a critic.

## Rationale
Tickets created by the LLM today follow a thin format and a developer-voice persona, with no way to express relationships between work items. BH-003, BH-004, and BH-010 collectively address all three: relationship fields (BH-003), PM persona + new sections + product-manager skill (BH-004), and second-LLM critic on drafts (BH-010). Bundling keeps the ticket-format changes coherent and avoids two formats coexisting mid-rollout.

## Tickets
- BH-003 — Ticket relationships (related / blocks / blocked-by)
- BH-004 — Reframe BOTHORDE.md persona + product-manager skill
- BH-010 — Second-LLM review pass on ticket drafts

## Status
In progress
