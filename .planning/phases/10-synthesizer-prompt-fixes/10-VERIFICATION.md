---
status: passed
phase: 10
phase_name: Synthesizer Prompt & Context Fixes
verified_on: 2026-05-07
verified_by: gap-closure-execution
closes_audit_gaps: [G1, G3, G5]
---

# Phase 10 Verification — Synthesizer Prompt & Context Fixes

## Method

Static verification of deliverables against `10-01-PLAN.md` acceptance
criteria. Runtime verification deferred to PR test plan (live macOS
populated machine).

## Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | History file read added before Step 2m synthesizer invocation | ✓ | SKILL.md `### Pre-call: load history file for ETA self-tuning` block, line 351 — `HIST_FILE`/`HISTORY_JSON` populated from `$HOME/.claude/data/upkeep-history.json` or `'{}'` |
| 2 | Synthesizer prompt's third input block uses the shell variable | ✓ | SKILL.md `History (may be empty):` block now reads `${HISTORY_JSON}` instead of the literal `{{ paste ... }}` placeholder |
| 3 | Hard Rule #8 (macOS restart_required propagation) added | ✓ | SKILL.md Hard Rules block — rule 8 instructs synthesizer to set `tool_specs.macos.{kind,command,restart_required,preconditions}` when `native.softwareupdate.restart_required` is true |
| 4 | 08-CONTEXT.md `tool_specs` example shows `macos` entry | ✓ | `.planning/phases/08-compatibility-synthesizer/08-CONTEXT.md` `tool_specs` example now ends with a `"macos"` block; clarifying paragraph below the JSON explains the gating from `softwareupdate.restart_required` |
| 5 | Hard Rule #1 extended to consume severity fields and sort warnings | ✓ | SKILL.md Hard Rule #1 now requires reading `severity_on_major` / `severity_on_minor` and sorting `plan.warnings[]` by severity high → medium → low |
| 6 | SKILL.md frontmatter still parses; markdown fences still balanced | ✓ | `awk` fence count: 46 (23 pairs, even). Frontmatter `---` markers unchanged. |
| 7 | Closes audit gaps G1, G3, G5 | ✓ | All three gap descriptions in `v1.1-MILESTONE-AUDIT.md` are now addressed by edits in this phase |

## T1–T3 (sub-tasks from PLAN)

| T | Task | Status |
|---|---|---|
| T1 | Wire history file read into Step 2m | ✓ Bash block added; placeholder replaced with `${HISTORY_JSON}` |
| T2 | Add Hard Rule #8 + 08-CONTEXT macos shape | ✓ Both files updated |
| T3 | Extend Hard Rule #1 for severity tiers | ✓ Rule rewritten to read both severity fields and sort warnings |

## Gap mapping

| Audit gap | Resolution | Strength |
|---|---|---|
| G1 — R10 history reader unwired | T1 reads file into `$HISTORY_JSON`; prompt interpolates it. Hard Rule #6 (median-of-5) is now load-bearing on the second run onward. | Fully closed (static); runtime verifies on second run. |
| G3 — R5 `tool_specs.macos.restart_required` field unspecified | T2 adds Hard Rule #8 + 08-CONTEXT example. Step 3m's existing restart-warning gate (line ~553) will now find the field populated. | Fully closed (static); runtime verifies on a system with pending macOS update. |
| G5 — severity fields unused | T3 extends Hard Rule #1. Risks block in Step 5m surfaces high-severity flags above medium/low. | Fully closed (static); runtime visible in any populated run. |

## Out-of-scope items (deferred per PLAN)

- Changes to `compatibility.json` data — severity fields already exist
- Changes to scouts (Phase 7) or apply orchestrator (Phase 9) — Phase 11 covers apply side

## Verdict

**PASSED.** All static deliverables present and matching the plan.
G1, G3, G5 closed in source.
