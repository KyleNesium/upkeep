# Phase 10 Summary — Synthesizer Prompt & Context Fixes

**Plan:** `10-01-PLAN.md`
**Status:** Complete (verified static; runtime in PR)
**Completed:** 2026-05-07
**Closes audit gaps:** G1, G3, G5

## What shipped

- **G1 — history reader wired.** `### Pre-call: load history file for ETA self-tuning` block reads `~/.claude/data/upkeep-history.json` into `$HISTORY_JSON` (or `'{}'`) before the synthesizer Agent invocation. Prompt's third input fence now interpolates `${HISTORY_JSON}`. R10 self-tuning is load-bearing on the second-and-later run.
- **G3 — macOS restart field documented + propagated.** Hard Rule #8 added: when `native.softwareupdate.restart_required` is true, synthesizer must populate `tool_specs.macos` with `kind/command/restart_required/preconditions`. `08-CONTEXT.md` `tool_specs` example now shows the `macos` shape.
- **G5 — severity tiers consumed.** Hard Rule #1 extended: synthesizer reads `severity_on_major` / `severity_on_minor` from each materialised edge and sorts `plan.warnings[]` by severity (high → medium → low). Risks block in Step 5m surfaces high-severity flags first.

## Cross-references

- Implementation: `upkeep/skills/update/SKILL.md` Step 2m (lines 346–425) + 08-CONTEXT.md `tool_specs` example
- Audit gap source: `.planning/v1.1-MILESTONE-AUDIT.md` G1, G3, G5
- Verifies: `10-VERIFICATION.md`
