---
name: upkeep:cleanquick
version: 1.8.0
author: KyleNesium
description: |
  Fast cache sweep. v1.8 single-shot: a two-turn wrapper over the `clean.sh`
  engine in quick mode — the lightweight subset (dev caches, Electron caches,
  Trash on macOS; ~/.cache on Linux). Build artifacts are reported but NOT
  removed in quick mode (run cleandeep for those). Turn 1 discovers + renders
  one approval gate; turn 2 applies the approved set. All deletion goes through
  the hardened path-safety validator with per-item failure isolation. Good for
  routine monthly maintenance. Typical recovery: 1–5GB.
  Use when: "quick clean", "fast cleanup", "just caches", "routine cleanup",
  "quick sweep", "just clean caches", "quick mac cleanup".
allowed-tools:
  # The cleanup engine is the ONLY mutation path (A1 trust boundary)
  - Bash(bash *clean.sh *)
  - Bash(uname *)
  - Bash(df *)
  - Bash(du *)
  - Bash(sw_vers *)
  - Bash(echo *)
  - Read
  - Glob
  - Grep
---

# /upkeep:cleanquick — Fast Cache Sweep

Exactly **two turns**. Turn 1 discovers + renders the gate and ENDS at the
`AskUserQuestion`. Turn 2 applies and renders the report. `${CLAUDE_SKILL_DIR}`
is this SKILL.md's absolute directory; the engine lives in the umbrella skill's
`scripts/` dir.

## Turn 1 — Discover + gate

```bash
bash "${CLAUDE_SKILL_DIR}/../upkeep/scripts/clean.sh" discover quick
```

Quick mode scans only the lightweight categories and marks **build_artifacts as
`report_only`** (shown for awareness, never removed here). Expensive scans are
time-bounded; a `warnings[]` entry notes any truncation.

JSON shape: `{manifest_file, category_counts, total_reclaimable_bytes,
warnings[], manual_steps[], needs_approval, item_count}`.

- `item_count == 0` → "Nothing to clean — caches are already lean." Stop.
- Otherwise render the gate (non-zero categories only), note that
  build_artifacts is report-only ("run `/upkeep:cleandeep` to remove those"),
  show `warnings[]` + `manual_steps[]`, print the deletion disclaimer:

```
⚠ Cleanup deletes files. Quick mode removes only caches/Trash that rebuild;
  build artifacts are listed but kept. Review before approving.
```

Then a single `AskUserQuestion`:
- A) Apply all (caches + Trash)  *(recommended)*
- B) Drop categories
- C) Cancel

On **B**, a second multi-select for the non-zero categories → `$DROP_CSV`.

**End the turn at the `AskUserQuestion`.**

## Turn 2 — Apply

```bash
bash "${CLAUDE_SKILL_DIR}/../upkeep/scripts/clean.sh" apply "$MANIFEST_FILE" \
  ${DROP_CSV:+--drop="$DROP_CSV"}
```

Same engine guarantees as cleandeep (TTL, re-validation, TOCTOU re-stat,
Electron pgrep recheck, per-item isolation). `report_only` build artifacts are
never deleted even under "Apply all". Surface an `error` field if present.

### Report render

```
── Quick Clean Report ──────────────────────────────────
  Removed:   <applied_count> items, ~<reclaimed_bytes> reclaimed
  Skipped:   <skipped_count> (<reasons>)
  Failed:    <failed_count> (<reasons>)
  Build artifacts: reported only — run /upkeep:cleandeep to remove
```

## Rules

- Two turns, always. The engine is the only mutation path — no direct `rm`.
- Quick never removes build artifacts (report_only) — that's cleandeep territory.
- Never run sudo — system-package work is surfaced as manual steps.
