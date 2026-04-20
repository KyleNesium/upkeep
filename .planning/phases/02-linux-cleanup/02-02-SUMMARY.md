---
phase: 02-linux-cleanup
plan: 02
subsystem: skills
tags: [cleandeep, linux, wsl2, journalctl, systemd, cache]

# Dependency graph
requires:
  - phase: 02-01
    provides: Phase 1+2 Linux branches and OS detection in cleandeep

provides:
  - "Phase 3 Step 3: Linux user cache approval gate with per-subdir removal and warn list"
  - "Phase 9: Linux journalctl disk-usage reporting and user-journal vacuum with approval"
  - "Phase 9: macOS ~/Library/Logs scans wrapped in OS_TYPE=macos guard"

affects: [02-03, 02-04, 02-05, cleandeep]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Linux approval gate: present numbered table, per-index removal, never blanket directory wipe"
    - "journalctl user-journal vacuumed without sudo; system journal surfaced as manual step"
    - "macOS-centric phase body wrapped in OS_TYPE guard to prevent Linux noise"

key-files:
  created: []
  modified:
    - "upkeep/skills/cleandeep/SKILL.md"

key-decisions:
  - "Phase 3 Linux step added as Step 3 after existing cross-platform Step 2, not replacing it"
  - "NEVER clear ~/.cache/ as whole directory — only named subdirs approved by user"
  - "Warn list for slow-to-rebuild caches: mesa_shader_cache, fontconfig, nvidia"
  - "User journal vacuumed at 200M threshold; system journal surfaced as sudo manual step"
  - "Phase 9 macOS log scans individually wrapped in OS_TYPE=macos guards"

patterns-established:
  - "Per-subdir approval table pattern: index, path, size — user selects by index"
  - "sudo commands surface only in prose blockquotes or ## Manual Steps, never in executable fences"

requirements-completed: [LNX-03, LNX-04]

# Metrics
duration: 1min
completed: 2026-04-17
---

# Phase 02 Plan 02: Linux User Cache and Journal Cleanup Summary

**Approval-gated ~/.cache/ removal with per-subdir selection and journalctl vacuum for cleandeep Phases 3 and 9 on Linux/WSL2**

## Performance

- **Duration:** 1 min
- **Started:** 2026-04-17T12:31:47Z
- **Completed:** 2026-04-17T12:32:57Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Phase 3 gains a Linux-only Step 3 that reports total ~/.cache/ size and top-15 subdirs sorted by size, with per-subdir approval gate and safety warn list for slow-to-rebuild caches
- Phase 9 now reports journalctl --disk-usage and --user --disk-usage on Linux/WSL2; vacuums the user journal to 200MB on approval; surfaces system journal vacuum as a sudo Manual Step
- Existing Phase 9 macOS ~/Library/Logs scans wrapped in OS_TYPE=macos guard to prevent empty-output noise on Linux

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Linux ~/.cache approval flow to Phase 3** - `76b591f` (feat)
2. **Task 2: Add journalctl vacuum to Phase 9** - `3be13dc` (feat)

**Plan metadata:** _(pending final docs commit)_

## Files Created/Modified
- `upkeep/skills/cleandeep/SKILL.md` - Added Phase 3 Step 3 (Linux cache approval) and Phase 9 Linux journalctl block with macOS guard around existing log scans

## Decisions Made
- Phase 3 Linux approval flow added as **Step 3** after existing cross-platform Step 2 — keeps discovery scan universal, adds Linux-specific removal approval separately
- NEVER clear `~/.cache/` as a whole directory; only named subdirs approved by user — critical UX safety: mesa_shader_cache and fontconfig rebuild slowly and impact desktop startup
- System journal vacuum (`sudo journalctl --vacuum-size=500M`) surfaces only as prose blockquote under Manual Steps — never in an executable bash fence — so the skill never invokes sudo
- All three existing macOS log scan fences individually wrapped in `if [ "$OS_TYPE" = "macos" ]` guards

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- LNX-03 and LNX-04 complete; Phase 3 and Phase 9 of cleandeep are now fully cross-platform
- Plans 03, 04, 05 of Phase 02 already completed (executed out-of-order per prior sessions)
- Phase 02 linux-cleanup now fully delivered

---
*Phase: 02-linux-cleanup*
*Completed: 2026-04-17*
