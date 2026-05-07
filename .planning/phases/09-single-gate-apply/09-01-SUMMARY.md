# Phase 9 Summary — Single-Gate Apply + Post-Flight

**Plan:** `09-01-PLAN.md`
**Status:** Complete (verified static; runtime in PR #8)
**Completed:** 2026-05-07

## What shipped

- Single approval gate in Step 3m (Apply all / Drop categories /
  Cancel). Drop-categories follow-up is a multi-select AskUserQuestion.
- Apply orchestrator with three parallelism modes:
  - `serial` — sequential per group (skills, stores)
  - `exclusive` — single command (brew)
  - `parallel` — fan-out via `Bash run_in_background`, 4-job cap
    (language ecosystems)
- Per-tool failure isolation: each command wrapped in `if ! eval ... fi`,
  failures recorded as `RESULT=fail:$?` and never block other tools or
  groups.
- macOS update restart warning preserved as an explicit second-tier gate
  even under "Apply all".
- Audit-mode short-circuit: when sub-mode is `audit`, Phase 9 stops
  after rendering the plan as the report.
- Post-flight (Step 4m):
  - `brew doctor` filtered for "Your system is ready to brew" (silent
    on clean)
  - PATH shadow re-check via `which -a` for every upgraded brew
    formula's binaries
  - Resolution re-check via `command -v` for each upgraded tool
  - Deprecation aggregator across npm/gem/pipx stdout, deduped/sorted,
    capped at 20 entries
- Final report (Step 5m) with `⚠ Risks observed`, `Manual steps`, and
  per-tool ✓/↷/✗ table.
- History writer at `~/.claude/data/upkeep-history.json` with atomic
  `.tmp` + `mv` write, graceful no-jq fallback message.

## What's deferred

- Rollback automation (snapshot before upgrade) — manual hints only.
- Email/Slack notifications — defer.
- Recursive scheduling (cron) — defer.

## Cross-references

- Implementation: `upkeep/skills/update/SKILL.md` lines 410–565
- Phase 8 plan consumed via `ordered_groups` + `tool_specs`.
- History file feeds Phase 8's ETA heuristic on the next run.
- PR: #8
