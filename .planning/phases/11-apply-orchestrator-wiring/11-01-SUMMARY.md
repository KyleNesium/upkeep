# Phase 11 Summary — Apply Orchestrator Wiring

**Plan:** `11-01-PLAN.md`
**Status:** Complete (verified static; runtime in PR)
**Completed:** 2026-05-07
**Closes audit gaps:** G2, G4

## What shipped

- **G4 — schema-version refusal gate.** New `### Schema gate (check first)` block at the top of Step 3m. Uses `jq -e '.schema_version == "1"'` to reject mismatched plans; on fail, swaps in `$FALLBACK_PLAN_JSON` and surfaces the existing fallback string (`compatibility analysis unavailable — running in fallback mode`). Skipped silently when `jq` is missing — same graceful degradation as Step 5m's history writer.
- **G2 — `$UPGRADED_FORMULAS` / `$UPGRADED_TOOLS` populated.** Apply orchestration now opens with `mktemp` + `trap` for two accumulator files. The per-tool isolation wrapper appends to `$UPGRADED_FORMULAS_FILE` (brew formulas, parsed from `==> Upgrading` log lines) or `$UPGRADED_TOOLS_FILE` (everything else) on success. After all groups complete, `sort -u` populates and exports the env vars Step 4m's existing loops consume.

## Race safety

`language` group runs concurrent writers to `$UPGRADED_TOOLS_FILE`. POSIX guarantees atomic writes ≤ `PIPE_BUF` (4096 bytes on macOS); single-line `echo "$TOOL"` writes are well under that. No locking needed.

`brew` is parallelism-mode `exclusive` so its writer is single-threaded.

## Cross-references

- Implementation: `upkeep/skills/update/SKILL.md` Step 3m schema gate (line 439) + apply orchestration (lines 498–545)
- Audit gap source: `.planning/v1.1-MILESTONE-AUDIT.md` G2, G4
- Verifies: `11-VERIFICATION.md`
