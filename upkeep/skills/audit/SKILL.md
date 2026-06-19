---
name: upkeep:audit
version: 1.8.0
author: KyleNesium
description: |
  Full system disk audit — report only, never removes anything. v1.8 single-shot:
  one `clean.sh discover audit` pass emits a complete manifest and the skill renders
  it as a report. Covers dev caches, build artifacts, Electron caches, Xcode
  DerivedData/Archives, iOS backups, large files, orphaned LaunchAgents, and
  Homebrew/Docker reclaimable space on macOS; ~/.cache, snap/flatpak, and
  apt/dnf/pacman package cache on Linux/WSL2. Reports sizes and findings; makes
  zero changes. audit mode never truncates — it always produces a complete picture.
  Use when: "audit my mac", "scan my mac", "what's taking up space",
  "report only", "just check", "don't remove anything", "what can I clean",
  "what's using space".
allowed-tools:
  # The cleanup engine (read-only in audit mode — never reaches apply)
  - Bash(bash *clean.sh *)
  # Read-only environment queries for the report header
  - Bash(uname *)
  - Bash(df *)
  - Bash(du *)
  - Bash(sw_vers *)
  - Bash(echo *)
  - Read
  - Glob
  - Grep
---

# /upkeep:audit — System Disk Audit (report only)

Read-only. **One turn**: run discovery, render the report, stop. This skill
**NEVER** applies — there is no apply step in audit mode.

## Run discovery

The cleanup engine lives in the umbrella skill's `scripts/` dir. The harness
provides this SKILL.md's absolute directory as `${CLAUDE_SKILL_DIR}`.

```bash
bash "${CLAUDE_SKILL_DIR}/../upkeep/scripts/clean.sh" discover audit
```

The script auto-detects the OS and prints SKILL-facing JSON:

```
{ manifest_file, mode:"audit", os, category_counts, item_count,
  total_reclaimable_bytes, warnings[], manual_steps[], protected_skipped[],
  needs_approval:false }
```

`audit` always runs every scan section to completion (no time-budget
truncation), so totals are trustworthy.

## Render the report

Render a table from `category_counts` and `total_reclaimable_bytes` (convert
bytes to human units). Only show categories with a non-zero count.

```
## Audit Report

| Category | Items | Reclaimable | Notes |
|----------|-------|-------------|-------|
| dev_caches | N | ...GB | rebuildable |
| build_artifacts | N | ...GB | report-only; rebuildable |
| electron | N | ...MB | per-app caches (not running) |
| xcode | N | ...GB | DerivedData safe; Archives may be kept |
| ios_backup | N | ...GB | local device backups |
| large_file | N | ...MB | installers/archives in Downloads/Desktop |
| launchagent | N | — | orphaned (target missing) |
| brew / docker | N | ...GB | reclaimable via cleanup/prune |
| snap / flatpak | N | ...MB | Linux: disabled revisions / unused runtimes |
| **Total reclaimable** | | **...GB** | |
```

Then surface, if non-empty:
- `warnings[]` — one line each (e.g. rebuild-costly caches, scan truncation).
- `manual_steps[]` — verbatim; on Linux these are the `sudo apt/dnf/pacman`
  system-package commands upkeep never runs.
- `protected_skipped[]` — only if you want to show what was deliberately skipped.

End with: **"Audit complete — nothing changed. Run `/upkeep:cleandeep` to clean up, or `/upkeep:cleanquick` for a fast cache sweep."**

## Rules

- **Report only.** Never call `clean.sh apply`. Never run any mutating command.
- The `manifest_file` is left on disk for reference; do not act on it.
- The engine is the single source of truth — do not re-implement scans in prose.
