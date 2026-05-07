---
phase: 02-linux-cleanup
plan: 03
subsystem: skills
tags: [cleandeep, snap, flatpak, linux, wsl2, cleanup]

# Dependency graph
requires:
  - phase: 02-linux-cleanup/02-02
    provides: Phase 3 Linux user cache approval and Phase 9 journal vacuum added to cleandeep

provides:
  - Phase 16 (Snap & Flatpak cleanup) appended to cleandeep phase sequence for Linux/WSL2
  - Approval-gated snap disabled revision removal via snap remove --revision
  - Approval-gated flatpak unused runtime removal via flatpak uninstall --unused --assumeyes
  - Phase 16 row in Final Summary table
affects: [02-linux-cleanup/02-04, 02-linux-cleanup/02-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - command -v guard for optional tool presence before phase logic
    - OS guard at phase entry (linux/wsl2 check) before any tool commands
    - sudo surfaced as Manual Steps prose block only — never in executable fence

key-files:
  created: []
  modified:
    - upkeep/skills/cleandeep/SKILL.md

key-decisions:
  - "Phase 16 placed after Phase 15 (pipx) and before Reporting — mirrors macOS optional-tool tail pattern"
  - "sudo snap remove and sudo flatpak uninstall shown in fenced blocks with comment noting Manual Steps context, matching Phase 2/7/9 pattern throughout skill"

patterns-established:
  - "Snap disabled revision removal: snap list --all | awk '/disabled/' → numbered table → snap remove --revision=<rev> <pkg>"
  - "Flatpak unused runtime removal: flatpak list --runtime → yes/no prompt → flatpak uninstall --unused --assumeyes"

requirements-completed: [LNX-05]

# Metrics
duration: 1min
completed: 2026-04-17
---

# Phase 02 Plan 03: Snap & Flatpak Cleanup (cleandeep Phase 16) Summary

**cleandeep gains Phase 16: approval-gated snap disabled revision removal and flatpak unused runtime cleanup on Linux/WSL2, both command-v guarded, with OS guard skipping silently on macOS**

## Performance

- **Duration:** 1 min
- **Started:** 2026-04-17T12:35:18Z
- **Completed:** 2026-04-17T12:36:40Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Inserted `## Phase 16: Snap & Flatpak Cleanup (Linux/WSL2)` between Phase 15 (pipx) and `## Reporting`
- Phase 16 includes OS guard that silently skips with one-line message on macOS
- Step 1 (Snap): `command -v` guard, lists installed packages + disk usage + disabled revisions, approval-gated `snap remove --revision=<rev> <pkg>` per approved entry
- Step 2 (Flatpak): `command -v` guard, lists apps/runtimes/usage, approval-gated `flatpak uninstall --unused --assumeyes`
- Added `| 16| Snap & Flatpak |` row to Final Summary table between Phase 15 and Total rows

## Task Commits

Each task was committed atomically:

1. **Task 1: Insert Phase 16 (Snap & Flatpak) between Phase 15 and Reporting** - `4e161c4` (feat)
2. **Task 2: Update Cleanup Report table to include Phase 16** - `92341a6` (feat)

**Plan metadata:** TBD (docs: complete plan)

## Files Created/Modified
- `upkeep/skills/cleandeep/SKILL.md` - Added Phase 16 Snap & Flatpak section (71 lines) and Phase 16 row in Final Summary table

## Decisions Made
- Phase 16 placed after Phase 15 (pipx) and before Reporting — mirrors macOS optional-tool tail pattern
- sudo commands for both snap and flatpak shown in bash fences following the established Phase 2/7/9 pattern (prose before fence says "surface under ## Manual Steps"), consistent with the rest of cleandeep

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 16 complete; cleandeep now covers all Linux sandboxed app formats
- Ready for 02-04 and 02-05 (remaining linux-cleanup plans)

---
*Phase: 02-linux-cleanup*
*Completed: 2026-04-17*
