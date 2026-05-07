# Phase 11 Context — Apply Orchestrator Wiring (gap closure)

## Goal

Close two gaps identified in the v1.1 milestone audit (2026-05-07) that
live in the Step 3m apply orchestrator and Step 4m post-flight.

## Gaps closed

| Gap | Tied to | Today | Target |
|---|---|---|---|
| G2 | R7 (PATH shadowing) | Step 4m loops at lines 499 and 514 iterate `$UPGRADED_FORMULAS` and `$UPGRADED_TOOLS` but Step 3m never populates these vars. Runtime: silent no-op. | Step 3m's per-tool isolation wrapper appends to the appropriate var on success; brew formulas → `$UPGRADED_FORMULAS`, everything else → `$UPGRADED_TOOLS`. |
| G4 | tech debt | `08-CONTEXT.md` says "Phase 9 refuses to apply on schema mismatch" but Step 3m has no `schema_version` check. Synthesizer fallback covers timeout/invalid output but not "valid JSON, wrong schema". | Add a one-line `jq -e '.schema_version == "1"'` check before the approval gate; on fail, surface the existing fallback string and run the rule-based plan. |

## Inputs

- `upkeep/skills/update/SKILL.md` Step 3m (lines ~414–485) and Step 4m
  (lines ~488–520)
- `.planning/phases/08-compatibility-synthesizer/08-CONTEXT.md` — the
  schema_version contract that Phase 9 is supposed to enforce
- `.planning/v1.1-MILESTONE-AUDIT.md` — gap descriptions

## Outputs

- Edits to `upkeep/skills/update/SKILL.md` Step 3m only.
- No changes to Step 4m (the loops there are correct; they just had no
  upstream populator).
- No changes to `compatibility.json`.

## Constraints

- Backwards-compatible: if the synthesizer emits a valid `schema_version: "1"`
  plan (as it does today), the new check is a no-op pass-through.
- The fallback string ("compatibility analysis unavailable — running in
  fallback mode") must be reused — don't introduce a parallel string.
- No new external deps. `jq` is already used elsewhere in Step 5m and is
  documented as optional with a graceful fallback message.

## Risks

- If `jq` is not installed, the schema check should pass through (not
  block) — this matches the existing behaviour in Step 5m's history
  writer.
- Variable accumulation across parallel apply: `$UPGRADED_FORMULAS` is
  appended to from a parallel-language group via `run_in_background`.
  Need to either:
  - Append to a temp file and read at the end (race-free), or
  - Append in a serialised post-group aggregation step.
  The plan picks the temp-file approach because it's idiomatic for
  this skill.

## Open questions

None. The audit's recommended fixes (G2 + G4) are specific enough to
execute directly.
