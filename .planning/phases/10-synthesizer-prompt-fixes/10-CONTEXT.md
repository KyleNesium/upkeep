# Phase 10 Context — Synthesizer Prompt & Context Fixes (gap closure)

## Goal

Close three gaps identified in the v1.1 milestone audit (2026-05-07) that
all live in or near the Step 2m synthesizer prompt and the
`08-CONTEXT.md` schema example.

## Gaps closed

| Gap | Tied to | Today | Target |
|---|---|---|---|
| G1 | R10 (ETA self-tuning) | Synthesizer prompt's `History (may be empty)` block is a literal `{{ paste ... }}` placeholder; no preceding bash reads `~/.claude/data/upkeep-history.json`. ETA always falls back to bake-ins. | A pre-Step-2m bash snippet reads the history file into a shell var; the prompt block is rewritten to inject that var (or `{}` if missing). |
| G3 | R5 (single gate macOS-restart leg) | Step 3m line 477 reads `plan.tool_specs.macos.restart_required`, but synthesizer Hard Rules don't say to set it; `08-CONTEXT.md` `tool_specs` example is silent on `macos`. | Add a Hard Rule: *"If `native.softwareupdate.restart_required` is true, set `tool_specs.macos.restart_required: true` and include `macos` in `stores`."* Update 08-CONTEXT.md schema example to show `macos` shape. |
| G5 | tech debt | `compatibility.json` edges carry `severity_on_major` / `severity_on_minor` but synthesizer prompt never references them; risk flagging is binary. | Extend Hard Rule #1 (matrix-only edges) so synthesizer reads the severity fields and tiers the Risks render (high above medium, medium above low). |

## Inputs

- `upkeep/skills/update/SKILL.md` Step 2m (lines ~346–408)
- `upkeep/skills/update/compatibility.json`
- `.planning/phases/08-compatibility-synthesizer/08-CONTEXT.md`
- `.planning/v1.1-MILESTONE-AUDIT.md` — gap descriptions and fix recommendations

## Outputs

- Edits to `upkeep/skills/update/SKILL.md` Step 2m only.
- Edits to `.planning/phases/08-compatibility-synthesizer/08-CONTEXT.md` schema example.
- No changes to `compatibility.json` (the data is fine; the prompt just needs to consume the existing severity fields).

## Constraints

- Backwards-compatible: existing scout JSON shape unchanged; new behaviour
  triggers from existing fields.
- No new external deps (N1 preserved).
- Single-file SKILL.md preserved (N2).
- Fallback path (synthesizer Agent failure) untouched — these fixes
  affect the happy path only.

## Risks

- Adding Hard Rules increases prompt length; agents handle ~20 rules
  comfortably. We're going from 7 to 8 rules — well within tolerance.
- Severity tiering changes the Risks render order; visual diff risk on
  the report. Acceptable since high-severity flags surfacing first is the
  goal.
