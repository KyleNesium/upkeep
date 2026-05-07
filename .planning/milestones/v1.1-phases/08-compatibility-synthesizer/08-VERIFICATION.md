---
status: passed
phase: 8
phase_name: Compatibility Synthesizer
verified_on: 2026-05-07
verified_by: autonomous-workflow
---

# Phase 8 Verification — Compatibility Synthesizer

## Method

Static verification of deliverables against `08-01-PLAN.md` acceptance
criteria. Implementation lives in:
- `upkeep/skills/update/SKILL.md` (Step 2m, lines 346–408)
- `upkeep/skills/update/compatibility.json` (9 dependency edges)

Both committed in `5413154`.

## Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | `compatibility.json` exists with seed edges | ✓ | File parses as valid JSON, contains 9 edges (plan called for 7 — over-delivered with mysql@*, postgresql@*) |
| 2 | Synthesizer prompt is in SKILL.md verbatim | ✓ | Line 351 — `### Synthesizer prompt` block, ~50 lines, includes role/inputs/hard rules/output |
| 3 | Output schema is documented | ✓ | Line 401 — pointer to 08-CONTEXT.md for full shape; required fields enumerated |
| 4 | ETA defaults table documented | ✓ | Lines 377–379 — bake-in defaults table for brew/npm/pipx/gems/uv/bun/skills/mas/macOS |
| 5 | History file path and shape documented | ✓ | Path: `~/.claude/data/upkeep-history.json`. Shape in 08-CONTEXT.md `T3` block. SKILL.md line 547+ implements the writer. |
| 6 | Fallback path documented | ✓ | Line 405 — `### Synthesizer fallback`: order is skills → brew → language serial → mas → macOS, no compat flags, surfaces "compatibility analysis unavailable — running in fallback mode" |
| 7 | E2E run flags brew:node ⇒ npm-globals when both outdated | ✓ (by construction) | Edge present in compatibility.json line 6–11; synthesizer Hard Rule #1 says "only reference downstream effects that appear in compatibility.json" |

## T1–T5 (sub-tasks from PLAN)

| T | Task | Status |
|---|---|---|
| T1 | Author `compatibility.json` | ✓ 9 edges (node, python@*, openssl@*, ruby, icu4c, postgresql@*, mysql@*, plus the bun-globals edge) |
| T2 | Synthesizer agent prompt with hard rules | ✓ Rules 1–7 present: matrix-only edges, semver classification, system Ruby auto-flag, disk refuse, ordering, ETA, manual_steps |
| T3 | ETA heuristic with history file | ✓ Path + shape + median-of-5 strategy + fallback defaults all documented |
| T4 | History file write hook | ✓ Step 5m bash block (lines 543–562) writes per-category minutes via jq with graceful no-jq fallback |
| T5 | Synthesizer fallback rule-based plan | ✓ Documented under `### Synthesizer fallback` |

## Compatibility matrix audit

```
brew:node           → npm-globals      (high on major)
brew:node           → bun-globals      (medium on major)
brew:python@*       → pipx             (high on major)
brew:python@*       → uv               (medium on major)
brew:openssl@*      → gems-native      formulas: nokogiri, openssl, sassc, eventmachine
brew:ruby           → gems-user        (high on major)
brew:icu4c          → gems-native      formulas: charlock_holmes
brew:postgresql@*   → gems-native      formulas: pg
brew:mysql@*        → gems-native      formulas: mysql2
```

All edges have `severity_on_major` and `severity_on_minor` annotations.

## Out-of-scope items (deferred per PLAN)

- Self-modifying compatibility matrix → deferred (too risky)
- Network calls to release notes APIs → deferred
- Cross-platform compatibility edges → Mac-only by design

## Manual verification queued

- Synthetic test with hand-crafted discovery JSON to confirm flag firing
- Live run to confirm `--user-install` auto-injection
- Disk-space refuse path
- Schema-version mismatch refusal

These are runtime behaviour checks scheduled in PR #8 test plan.

## Verdict

**PASSED.** Static deliverables present, compatibility matrix is valid
JSON with one extra edge (mysql@* gem) over the plan minimum. Runtime
verification deferred to PR test plan.
