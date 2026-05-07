---
status: passed
phase: 9
phase_name: Single-Gate Apply + Post-Flight
verified_on: 2026-05-07
verified_by: autonomous-workflow
---

# Phase 9 Verification — Single-Gate Apply + Post-Flight

## Method

Static verification of deliverables against `09-01-PLAN.md` acceptance
criteria. Implementation lives in `upkeep/skills/update/SKILL.md`
Steps 3m–5m (lines 410–565). Committed in `5413154`.

## Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Single approval gate replaces per-category gates on macOS | ✓ | Line 437 — single AskUserQuestion with 3 options (Apply all / Drop categories / Cancel) |
| 2 | "Drop categories" path is a second AskUserQuestion | ✓ | Line 443 — multi-select AskUserQuestion follow-up |
| 3 | Apply runs language group in parallel (4-cap) | ✓ | Line 455 — `parallelism: parallel → fan out via Bash run_in_background, cap 4 concurrent` |
| 4 | Post-flight: brew doctor + PATH shadow check + deprecation aggregation | ✓ | Step 4m bash block, lines 480–513: filter `Your system is ready to brew`, `which -a` per upgraded formula's binaries, `command -v` re-resolution, `sort -u $DEPRECATION_LOG` |
| 5 | Final report includes ⚠ Risks Observed and Manual Steps sections | ✓ | Step 5m, lines 518–527: both sections placed above the per-tool ✓/↷/✗ table |
| 6 | History file written after every successful apply | ✓ | Lines 545–562: jq-based atomic write to `~/.claude/data/upkeep-history.json` with no-jq fallback message |
| 7 | Audit sub-mode short-circuits before apply | ✓ | Line 446 — `If sub-mode is audit, **STOP HERE** — emit the plan as the report and skip apply + post-flight + history write` |
| 8 | Linux/WSL2 paths from v1.0 still work unchanged | ✓ | Steps 1–6 (line 569+) preserved verbatim; Routing block (line 154) directs non-macOS to those steps |

## T1–T8 (sub-tasks from PLAN)

| T | Task | Status |
|---|---|---|
| T1 | Approval gate (3 options + drop-cats follow-up) | ✓ Lines 414–445 |
| T2 | Apply orchestrator (serial / exclusive / parallel) | ✓ Lines 449–467 |
| T3 | Per-tool failure isolation | ✓ Line 460 — `if ! eval "$CMD" >>"$LOG" 2>&1; then RESULT=fail:$?; ... fi` |
| T4 | Post-flight checks | ✓ Step 4m bash block (480–513) |
| T5 | Deprecation aggregator | ✓ Line 463 — `tee` of warning lines into `$DEPRECATION_LOG`, deduped/sorted at line 512 |
| T6 | History file write | ✓ Lines 545–562, jq-based with `mkdir -p`, atomic via `.tmp` + `mv` |
| T7 | Final report layout | ✓ Step 5m structure includes all three sections (Risks Observed → Manual steps → Update Report) |
| T8 | Audit-mode short-circuit | ✓ Line 446 in Step 3m |

## Cross-phase integration check

| Integration | Status | Note |
|---|---|---|
| Phase 7 → Phase 8 | ✓ | Combined discovery JSON is the synthesizer's input |
| Phase 8 → Phase 9 | ✓ | `plan.ordered_groups` and `plan.tool_specs` consumed in Step 3m apply orchestrator |
| Phase 9 → Phase 8 (next run) | ✓ | History file written by Step 5m feeds ETA heuristic in Step 2m on next invocation |
| macOS routing → Linux/WSL2 routing | ✓ | Routing block (line 154) plus the warning at the top of `## Step 1` (line 571) prevent double execution |

## Manual verification queued

The plan calls for live test scenarios:
- Live run on populated machine (gate UX, parallel apply, post-flight surfacing)
- Synthetic failure injection (force brew upgrade fail mid-run)
- Audit-mode invocation
- History file accumulation across two runs
- Schema-version mismatch refusal

These are runtime behaviour checks captured in PR #8 test plan.

## Out-of-scope items (deferred per PLAN)

- Rollback automation (snapshot before upgrade) — manual hints only
- Email/Slack notifications — deferred
- Recursive scheduling (cron) — deferred

## Verdict

**PASSED.** All static deliverables present and matching the plan.
Runtime behaviour deferred to PR #8 test plan execution.
