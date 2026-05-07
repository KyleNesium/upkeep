# Phase 8 Summary — Compatibility Synthesizer

**Plan:** `08-01-PLAN.md`
**Status:** Complete (verified static; runtime in PR #8)
**Completed:** 2026-05-07

## What shipped

- `upkeep/skills/update/compatibility.json` — 9 dependency edges:
  `brew:node` → npm-globals + bun-globals; `brew:python@*` → pipx + uv;
  `brew:openssl@*` → gems-native (nokogiri, openssl, sassc, eventmachine);
  `brew:ruby` → gems-user; `brew:icu4c` → charlock_holmes;
  `brew:postgresql@*` → pg; `brew:mysql@*` → mysql2.
- Synthesizer agent prompt in `update/SKILL.md` Step 2m with seven
  hard rules:
  1. Matrix-only edges (no invented dependencies)
  2. Strict semver delta classification
  3. System Ruby auto-flag (`gem update --user-install`)
  4. Disk-space refuse path (< 5 GB → warning + empty plan)
  5. Group ordering (skills → brew → language → stores)
  6. ETA via history median, fallback to bake-in defaults
  7. Manual_steps for plugin-cache, PATH shadows, codex non-git skills
- ETA heuristic: median of last 5 runs from
  `~/.claude/data/upkeep-history.json`; bake-in defaults table for
  brew/npm/pipx/gems/uv/bun/skills/mas/macOS.
- Synthesizer fallback path (rule-based plan when agent fails).

## What's deferred

- Self-modifying compatibility matrix (LLM proposes new edges) — too
  risky for v1.1.
- Network calls to release notes APIs — CHANGELOG.md scan in Phase 7 is
  enough.
- Cross-platform compatibility edges — Mac-only by design.

## Cross-references

- Implementation: `upkeep/skills/update/SKILL.md` lines 346–408
- Matrix: `upkeep/skills/update/compatibility.json`
- Phase 7 inputs (combined discovery JSON) feed this phase.
- Phase 9 consumes this phase's `ordered_groups` + `tool_specs`.
- PR: #8
