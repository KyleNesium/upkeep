---
status: passed
phase: 11
phase_name: Apply Orchestrator Wiring
verified_on: 2026-05-07
verified_by: gap-closure-execution
closes_audit_gaps: [G2, G4]
---

# Phase 11 Verification — Apply Orchestrator Wiring

## Method

Static verification of deliverables against `11-01-PLAN.md` acceptance
criteria. Runtime verification deferred to PR test plan.

## Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Schema-version check added before approval gate | ✓ | SKILL.md Step 3m `### Schema gate (check first)` block uses `jq -e '.schema_version == "1"'`; on fail switches to `$FALLBACK_PLAN_JSON` |
| 2 | Existing fallback string reused verbatim | ✓ | Schema gate emits `compatibility analysis unavailable — running in fallback mode` — same string as `### Synthesizer fallback` block at line 434; no new strings introduced |
| 3 | `$UPGRADED_FORMULAS_FILE` / `$UPGRADED_TOOLS_FILE` declared in apply preamble with `trap` cleanup | ✓ | SKILL.md `### Apply orchestration` opens with `mktemp` for both files plus `trap "rm -f ..." EXIT` |
| 4 | Per-tool wrapper appends to the right file on success | ✓ | Wrapper now uses `case "$TOOL"` to route brew formulas (parsed from `==> Upgrading` lines) to `$UPGRADED_FORMULAS_FILE`, everything else to `$UPGRADED_TOOLS_FILE` |
| 5 | Pre-Step-4m env-var population reads from the files | ✓ | After all groups complete, `UPGRADED_FORMULAS=$(sort -u ... )` and `UPGRADED_TOOLS=$(sort -u ... )` populate + export the env vars Step 4m's loops consume |
| 6 | SKILL.md frontmatter still parses; markdown fences still balanced | ✓ | `awk` fence count: 46 (23 pairs, even); frontmatter unchanged |
| 7 | Closes audit gaps G2, G4 | ✓ | Both gaps from `v1.1-MILESTONE-AUDIT.md` resolved |

## T1–T2 (sub-tasks from PLAN)

| T | Task | Status |
|---|---|---|
| T1 | Schema-version refusal gate | ✓ Step 3m schema gate added before audit short-circuit |
| T2 | Populate `$UPGRADED_FORMULAS` / `$UPGRADED_TOOLS` | ✓ Temp-file accumulation pattern with `mktemp` + `trap` + `sort -u` |

## Gap mapping

| Audit gap | Resolution | Strength |
|---|---|---|
| G2 — R7 PATH shadow loop iterates undefined vars | Apply orchestration now populates `$UPGRADED_FORMULAS` / `$UPGRADED_TOOLS` via temp files. Step 4m loops at lines 580+ now have data to iterate. | Fully closed (static); runtime verifies once a brew upgrade runs. |
| G4 — schema_version refusal not implemented | Schema gate added at the top of Step 3m before any apply work. Wrong-schema plans route to fallback. | Fully closed (static); runtime tests by feeding a `schema_version: "2"` payload. |

## Race-safety note

The `language` group is parallelism-mode `parallel` and writes
concurrently to `$UPGRADED_TOOLS_FILE`. Appending one line per process
is atomic on POSIX systems for writes ≤ `PIPE_BUF` (4096 bytes on
macOS) — single-line `echo "$TOOL"` writes are well under that. No
locking needed.

For brew (parallelism: exclusive), there's only one writer to
`$UPGRADED_FORMULAS_FILE` so race-safety is trivial.

## Out-of-scope items (deferred per PLAN)

- Phase 8 changes (synthesizer prompt) — handled in Phase 10
- Adding new compatibility edges — v1.2+
- Improving brew log parsing for non-`==> Upgrading` lines — covers
  the common case; edge cases tracked separately if they appear

## Verdict

**PASSED.** All static deliverables present. G2 and G4 closed in
source. Race-safety addressed.
