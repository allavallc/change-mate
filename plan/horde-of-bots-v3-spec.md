# Horde of Bots v3.0 — Bot-Native Coordination

A spec for the next major version. The thesis: existing trackers (Jira, Linear, even the v2.0 of HoB) were designed assuming humans decide and humans do. v3.0 makes coordination bot-native while keeping the file-based contract that makes HoB readable in an afternoon.

This is a design doc, not a build order. Items are scoped tightly enough to become tickets but the order and priorities are subject to product input before implementation.

---

## Non-negotiables (carried from v2.0)

These are the constraints every v3.0 feature must respect. If a proposed feature can't be done within these limits, it doesn't ship.

1. **Files are the API.** Anyone with a clone and `cat` can read full state. The CLI is convenience, not contract.
2. **No required server, daemon, or backend.** A clone + git push/pull must be sufficient to participate fully.
3. **Read-in-an-afternoon.** Every added feature must be expressible in HORDEOFBOTS.md without bloating it past comprehensibility.
4. **Git remains the sync layer.** No other transport is required for the core workflow.
5. **MIT, no behind-paywall features in core.** A paid hosted layer (if it ever exists) is strictly additive.

These rules are why v3.0 looks the way it does. Several features below would be cleaner with a daemon — they are deliberately specced without one.

---

## The architectural call

The hard question for v3.0 is whether bot-native coordination requires a coordination service (daemon, scheduler, registry).

**Finding: it doesn't.** Every v3.0 feature listed below is expressible as file conventions, validators, and optional CLI helpers running on a clone. A daemon would make some features faster or more ergonomic, but none of them require one.

This matters because if the answer were "v3.0 needs a daemon," HoB becomes a platform — exactly the drift the CC review flagged. By staying file-based, v3.0 is an evolution of conventions, not a rewrite into a service.

If a hosted convenience layer is ever built, it sits *on top* of these conventions, doesn't replace them, and is opt-in.

---

## Audit-before-implement

Before specifying or building any item below, audit the current schema and CLAUDE.md for anything that already exists. The v2.0 review missed that `Blocks:` / `Blocked by:` was already implemented; that mistake is cheap to repeat. Each feature below has a "check first" note where existing functionality is plausible.

---

## Features

### 1. Lease-based claims

**Problem.** A claim today is a file move. There's no lease, no expiry, no formal way for the system to know a claim is stale beyond manual judgment. Bots crash, lose context, hit rate limits, and quietly stop working — but their tickets sit in `in-progress/` indefinitely.

**Check first.** v2.0 lightweight stale-detection (board surfaces "claimed Xh ago, last commit Yh ago") may already be in. If it is, this builds on it; if not, do that first.

**Approach.**
- Add `Lease-expires:` field to in-progress tickets, set at claim time to `now + default-lease` (default: 4h, configurable per-project in `config.json`).
- Agents extend their lease with `horde extend HB-XXX --hours N` while working. Each extension is a commit.
- After expiry, any agent may reclaim the ticket. Reclaim writes `Reclaimed-from: <previous-agent>` and resets the lease.
- The board renders lease state visibly: green (>2h remaining), yellow (<2h), red (expired).
- No daemon. Expiry is a property of the file's metadata, evaluated at read time by anything that cares.

**Done when.** Schema documents the field. Default lease and reclaim rules are in HORDEOFBOTS.md. Board renders lease status. CLI supports extend and reclaim. A test simulates a full cycle: claim → no extension → expiry → reclaim → completion.

---

### 2. Capability matching

**Problem.** Bots aren't interchangeable. One has prod access, one can run migrations, one is good at frontend, one only has read scope. Today every bot sees the full backlog and must self-filter — which means either over-claiming (taking work it can't finish) or under-claiming (skipping work it could have done).

**Approach.**
- New directory `horde-of-bots/agents/`, one file per agent: `agents/alex-bot.yaml` declaring capabilities:
  ```yaml
  agent: alex-bot
  capabilities: [frontend, ts, react, repo-write]
  budget-monthly-usd: 50
  ```
- Tickets declare requirements: `Requires: [frontend, repo-write]`.
- `horde claim` checks the claiming agent's capability file against the ticket's requirements and refuses if any required capability is missing (override with `--force` for manual operator action).
- `horde next` (item 9) only suggests tickets the requesting agent is qualified for.
- Validator (v2.0 #5) checks that all `Requires:` capabilities exist in the project's vocabulary, defined in `config.json`.

**Open question for product input.** Do capability files live in the main repo (committed, visible to everyone) or in agents' own configs (private, presented at claim time)? Committed is simpler and auditable; private respects operator separation. Recommendation: committed, because it preserves "files are the API."

**Done when.** Agent file format documented. Claim respects capabilities. Validator checks requirements. Board optionally renders capability badges on tickets and assignees.

---

### 3. Budget tracking and caps

**Problem.** Bot work has real cost — tokens, API calls, compute. Today there's no record of what a ticket cost, no way to cap spending per ticket, no rollup of project burn. A bot can blow $50 on a ticket that should have been $5 and nobody notices until the bill arrives.

**Approach.**
- Add to ticket schema: `Estimated-cost-usd:` (set at draft), `Actual-cost-usd:` (appended by agent on completion), `Budget-cap-usd:` (optional, hard cap).
- Agents report their incurred cost when they push state changes — either via `horde done --cost 3.42` or by appending to a `costs:` block in the ticket.
- `horde claim` refuses to claim a ticket whose `Estimated-cost-usd` exceeds the agent's remaining monthly budget (from the agent file in item 2).
- A `horde report` command rolls up actual vs. estimated cost across the project.
- The board shows cost on done tickets and a project-level burn bar.

**Open question.** Should the system enforce the budget cap mid-flight (force the bot to abort if `Actual-cost-usd > Budget-cap-usd`) or just record overruns? Enforcement requires the bot to cooperate by checking; recording is honest but toothless. Recommendation: record everywhere, enforce at claim time only. In-flight enforcement is the bot's responsibility.

**Done when.** Schema includes cost fields. CLI supports cost reporting on done. Board renders project burn. `horde report` exists. Tests cover cost rollups and budget-cap claim refusal.

---

### 4. Provenance schema

**Problem.** When something goes wrong — a bot ships a bad change, a ticket gets claimed and abandoned, two bots produce conflicting work — reconstructing what happened is painful. Git log shows commits but not the *why*: which model, which prompt, which artifacts produced.

**Approach.**
- Each state-change commit on a ticket includes structured trailers in the commit message:
  ```
  HB-003: claimed by alex-bot

  Agent: alex-bot
  Model: claude-opus-4-7
  Action: claim
  Triggered-by: horde-next
  ```
- Optionally, a `provenance.log` file lives alongside the ticket and accumulates a JSON-lines record of each event with the same metadata plus produced artifacts (commit SHAs, PR URLs, files changed).
- The CLI writes both automatically — agents don't author trailers by hand.
- A `horde audit HB-XXX` command reconstructs the full history from git log + provenance log.

**Done when.** Trailer format documented. CLI writes them on every state-change command. Provenance log format defined. `horde audit` works. Tests verify trailers survive a normal commit/push cycle.

---

### 5. Failure-state folders

**Problem.** Today a stuck ticket goes to `blocked/` regardless of why. Different stuck-states need different recoveries: a merge conflict needs a rebase, a context-exceeded failure needs a smaller scope, a failed-tests state needs a fix. Lumping them into `blocked/` loses information and slows recovery.

**Approach.**
- New folders alongside `blocked/`:
  - `failed-tests/` — work was done, tests fail, needs fix
  - `merge-conflict/` — rebase/merge issue, needs human or another bot to resolve
  - `context-exceeded/` — bot ran out of context, needs decomposition
  - `needs-review/` — bot completed work but flagged it for human verification
- Each folder has a documented recovery action in HORDEOFBOTS.md.
- `horde fail HB-XXX --reason <reason> --notes "..."` moves the ticket into the right folder and writes the reason.
- The board groups failure folders together visually under "needs attention."

**Open question.** How granular should the failure taxonomy be? Too few categories and the system loses information; too many and agents pick the wrong one. Recommendation: start with the four above, add only when a real recovery pattern emerges that doesn't fit.

**Done when.** Folders exist. Recovery actions documented per folder. CLI supports `fail`. Board groups them under a clear section.

---

### 6. Verification states

**Problem.** A bot saying "done" is not the same as a human or another bot saying "done." Today, `done/` is binary — work claimed complete by the assignee. There's no record of whether tests passed, whether anyone reviewed, or whether the change actually shipped.

**Approach.**
- Add `Verified-by:` and `Verification-method:` fields to done tickets.
- `Verification-method` is one of: `self-claimed`, `tests-passed`, `bot-reviewed`, `human-reviewed`, `shipped`.
- A ticket can accumulate multiple verifications: a bot says self-claimed, CI says tests-passed, a human says human-reviewed, a deploy says shipped.
- The board renders verification level visibly. `done/` tickets show their highest verification (a green checkmark for shipped, a yellow circle for self-claimed only, etc.).
- `horde verify HB-XXX --method <method> --by <name>` appends a verification.

**Done when.** Schema documents the fields. CLI supports `verify`. Board renders verification state. HORDEOFBOTS.md describes when each method is appropriate.

---

### 7. Concurrency limits as project rules

**Problem.** Some kinds of work shouldn't happen in parallel. Two bots editing `payments/` at once is a recipe for merge hell. A bot claiming work while CI is red is just queuing more failures. Today there's no way to express these rules; agents must self-regulate, and self-regulation across a horde is unreliable.

**Approach.**
- Project-level rules in `config.json`:
  ```json
  "concurrency-rules": [
    { "match": "path:payments/", "max-concurrent": 1 },
    { "match": "ci-status:red", "block-claims": true },
    { "match": "agent:*", "max-claims-per-agent": 2 }
  ]
  ```
- `horde claim` evaluates these rules against current `in-progress/` state and refuses violating claims with a clear message.
- Rules are checked locally on the claiming clone — no daemon. The agent reads `in-progress/` directory, checks rule matches, decides.
- CI-status rules require a small status file in the repo (`horde-of-bots/ci-status`) that CI updates on each run.

**Open question.** Path-based rules need a way to know which paths a ticket affects. Either tickets declare `Touches: [payments/, billing/]` explicitly, or the rule looks for keywords in the goal/notes. Recommendation: explicit `Touches:` field, validated by item 8.

**Done when.** Config format documented. Rule evaluator implemented. CLI refuses claims that violate rules. Tests cover each rule type.

---

### 8. Cross-repo dependencies

**Problem.** Real work spans repos. A ticket in `frontend/` depends on a fix in `backend/`. Today HoB has no way to express this; the dependency is invisible to the system, and bots in one repo have no way to see whether their upstream is done.

**Approach.**
- Add `Depends-on-external:` field referencing tickets in other repos:
  ```
  Depends-on-external:
    - repo: github.com/me/backend
      ticket: HB-042
  ```
- A `horde-of-bots/external-repos.yaml` config lists the other HoB repos this project knows about, with paths or URLs.
- `horde status` and `horde claim` check external dependencies by reading the referenced repo (either via local path or `git ls-remote` + sparse checkout of the relevant ticket file).
- The board renders cross-repo dependencies as faded badges, with a click-through if URLs are known.

**Open question — and this is the one most likely to push toward a daemon.** Cross-repo lookups require either local clones of all referenced repos or some form of remote read. Local clones work but require setup. A daemon could centralize this. Recommendation: start with local-clones-only, document the limitation, defer the daemon until someone is actually blocked by it.

**Done when.** Schema documents external dependencies. Config format defined. CLI resolves at least the local-clones case. Validator catches references to repos not listed in the config.

---

### 9. `horde next` — work request endpoint

**Problem.** Today an agent has to read the full backlog, filter for what it's qualified for, check dependencies, check budgets, check concurrency rules, and then pick. That logic lives in every agent's prompt. It's redundant and error-prone — and changes to the rules require updating every agent.

**Approach.**
- A single CLI command: `horde next --agent <name>`. Returns the highest-priority backlog ticket the agent is eligible for, given:
  - Capabilities (item 2)
  - Remaining budget (item 3)
  - Concurrency rules (item 7)
  - Dependencies, internal and external (item 8)
- Returns nothing (and an exit code) if there's no eligible work.
- The agent's instructions in HORDEOFBOTS.md become "run `horde next`, claim what it returns, do the work, mark done." Most of the decision logic moves out of agent prompts and into the CLI.

This is genuinely the load-bearing CLI feature. It's the one place where having a CLI rather than raw file ops actually changes the agent's job, because the eligibility logic is too complex to spell out in prose for every agent.

**Done when.** Command implemented. HORDEOFBOTS.md uses it as the primary "what should I do" pattern, with raw file browsing as fallback. Tests cover eligibility filtering across all rule types.

---

### 10. Decomposition and merge as first-class operations

**Problem.** Real bot work surfaces oversized tickets ("this is too big, split it") and duplicate tickets ("two bots filed the same bug"). Today both require manual file shuffling and lose provenance.

**Approach.**
- `horde split HB-003 --into "subtask-1" "subtask-2" "subtask-3"` creates new tickets, each with `Split-from: HB-003`. The original goes to a new state `split/` (or stays in done if already complete).
- `horde merge HB-005 HB-009 --winner HB-005` merges HB-009 into HB-005, archives HB-009 with `Merged-into: HB-005`, and consolidates relevant fields.
- Both operations are commits with proper provenance (item 4).

**Done when.** CLI supports split and merge. Schema documents the new fields. Validator catches references to merged or split-from tickets. HORDEOFBOTS.md describes when to use each.

---

### 11. Duplicate detection on creation

**Problem.** Bots filing tickets independently will produce near-duplicates ("fix login bug" / "users can't sign in"). Without a check, two bots end up working the same thing.

**Approach.**
- `horde new` runs an optional similarity check before committing the new ticket: compares the draft's goal/why against existing tickets and flags candidates for merge.
- Implementation calls an LLM or embedding API using the operator's own credentials (key in env var). HoB doesn't host this — the operator pays for the calls.
- If similar tickets are found, `horde new` shows them and asks the agent (or human operator) whether to proceed, merge, or cancel.

**Open question.** Embedding vs. LLM call. Embeddings are cheaper and faster but require local storage. An LLM call is simpler but costs more per use. Recommendation: LLM call by default, embedding as an optional optimization later.

**Done when.** `horde new` supports a similarity check (gated behind env var so it's opt-in). Documented in HORDEOFBOTS.md. A no-key path that skips the check exists for offline use.

---

## Suggested order

If everything above is in scope, this is a defensible build sequence:

1. **Item 1 (lease-based claims).** Foundation — most other features assume claims have lifecycles.
2. **Item 4 (provenance schema).** Cheap, additive, makes everything else auditable.
3. **Item 6 (verification states).** Cheap and immediately useful.
4. **Item 5 (failure-state folders).** Cheap, mostly file conventions.
5. **Item 2 (capability matching).** Foundation for items 3, 7, 9.
6. **Item 3 (budget tracking).** Builds on item 2.
7. **Item 7 (concurrency rules).** Builds on items 1, 2.
8. **Item 9 (`horde next`).** Pulls items 2, 3, 7, 8 together. Single highest-leverage CLI command.
9. **Item 10 (split/merge).** Independent, do whenever.
10. **Item 8 (cross-repo).** Hardest, defer until needed.
11. **Item 11 (duplicate detection).** Last — opt-in, requires external dependency, lowest immediate value.

Items 1–4 alone deliver a meaningfully more bot-native HoB without changing the surface area dramatically. Items 5–9 are the meat of v3.0. Items 10–11 are nice-to-haves.

---

## Deliberately not in v3.0

Calling these out so they don't get re-proposed mid-build:

- **A scheduling daemon.** No item above requires one. If hosted convenience is ever offered, it's additive.
- **A web app for humans to create/edit tickets.** Files-as-the-API means the editor is `$EDITOR`, not a webform. Read-only board stays read-only.
- **Real-time push notifications.** Polling stays the model. Notifications are an ecosystem concern (Slack/Discord integrations) not a core one.
- **Account systems, auth, multi-tenancy.** None of these belong in the file-based core.
- **A REST API.** The CLI is the API. The files are the API. A REST API would imply a server.
- **Built-in semantic search across tickets.** Item 11 covers the duplicate-on-creation case. General search is a nice-to-have layer that can be added by anyone with `grep` and 50 lines of script.

---

## What this spec doesn't decide

A few things deliberately deferred to product input:

- Whether agent capability files are committed to the main repo or kept private (item 2).
- Whether budget caps are mid-flight enforced or recording-only (item 3).
- The granularity of failure states (item 5).
- Whether cross-repo dependencies justify a daemon eventually (item 8).
- Embedding vs. LLM for duplicate detection (item 11).

These are choices that depend on the project's direction more than on engineering. CC can implement either side once decided.
