# [feature-set-012] Test infrastructure

## Goal
Test infrastructure that actually works — pytest invocation forms all succeed, regression tests verify real state, no silent passes.

## Rationale
Two pre-existing bugs surfaced during the fs-010 build (BH-071): the repo-root `conftest.py` adds the wrong path so specific-test pytest invocations fail, and a regression test still globs the pre-rename ticket prefix so it walks zero files. Bundled because both are "the test setup pretends to work but doesn't" — same shape at different layers. One-ticket feature set today; if similar rot surfaces, add to it.

## Tickets
- BH-079 — Post-rename test infrastructure cleanup

## Status
Backlog
