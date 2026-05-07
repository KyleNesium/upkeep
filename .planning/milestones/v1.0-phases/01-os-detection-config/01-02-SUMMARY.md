---
phase: 01-os-detection-config
plan: 02
subsystem: infra
tags: [os-detection, bash, cleandeep, linux, wsl2, macos, allowed-tools]

# Dependency graph
requires: []
provides:
  - OS detection snippet in cleandeep/SKILL.md (macos / linux / wsl2 + distro + pkg manager)
  - 11 new Linux allowed-tools entries in cleandeep frontmatter (uname, lsb_release, lsblk, cat, systemctl, journalctl, apt, dnf, pacman, snap, flatpak)
  - 6 macOS-only phase guards (Phases 2, 4, 5, 6, 11, 14) in cleandeep skill
affects: [02-linux-package-cleanup, 03-wsl2-support, cleandeep]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "OS_TYPE guard pattern: [ \"$OS_TYPE\" != \"macos\" ] at top of macOS-only skill phases"
    - "Canonical OS detection snippet: uname -s + uname -r for Darwin/Linux/WSL2 detection"

key-files:
  created: []
  modified:
    - upkeep/skills/cleandeep/SKILL.md

key-decisions:
  - "Guards placed BEFORE existing command -v brew/xcode-select checks so macOS path falls through to existing tool-availability checks unchanged"
  - "Phases 1, 3, 7-10, 12-13, 15 unguarded — cross-platform paths will get Linux steps in Phase 2 of roadmap"
  - "Version bumped to 1.1.0-dev to signal cross-platform work in progress"

patterns-established:
  - "macOS guard pattern: OS_TYPE bash conditional at phase entry, prose instruction follows immediately after code fence"
  - "allowed-tools ordering: OS detection group after PlistBuddy, Linux tools appended at end with section comments"

requirements-completed: [OS-01, OS-02, OS-03, OS-04, CFG-01]

# Metrics
duration: 13min
completed: 2026-04-17
---

# Phase 1 Plan 02: OS Detection & Config (cleandeep) Summary

**cleandeep skill made cross-platform: OS detection snippet, 11 Linux allowed-tools, and 6 macOS-only phase guards (2/4/5/6/11/14) leave macOS behavior identical while gracefully skipping on Linux/WSL2**

## Performance

- **Duration:** ~13 min
- **Started:** 2026-04-17T08:54:16Z
- **Completed:** 2026-04-17T09:07:00Z
- **Tasks:** 3
- **Files modified:** 1

## Accomplishments

- Extended `cleandeep/SKILL.md` frontmatter with 11 new Linux/cross-platform allowed-tools entries under properly commented sections
- Inserted canonical OS detection bash snippet as `## Environment Detection` section immediately before Phase 1, setting OS_TYPE/OS_DISTRO/PKG_MGR exported variables
- Added `$OS_TYPE != "macos"` guards to all 6 macOS-only phases (2, 4, 5, 6, 11, 14) with prose instruction to skip; preserved all existing `command -v` checks

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend cleandeep allowed-tools frontmatter** - `aedcfb8` (chore)
2. **Task 2: Insert OS detection snippet** - `1928af2` (feat)
3. **Task 3: Guard macOS-only phases 2, 4, 5, 6, 11, 14** - `ac93a75` (feat)

**Plan metadata:** (docs commit — see below)

## Files Created/Modified

- `upkeep/skills/cleandeep/SKILL.md` - Added 11 Linux allowed-tools, Environment Detection section, 6 OS guards; version bumped to 1.1.0-dev

## Decisions Made

- Guards placed BEFORE existing `command -v brew`/`command -v xcode-select` checks so macOS falls through naturally to existing tool-availability checks, preserving exact existing macOS behavior
- Phases 1, 3, 7-10, 12-13, 15 deliberately left unguarded as cross-platform; Linux-specific steps for those phases will be added in Phase 2 of the roadmap
- Version bumped to `1.1.0-dev` to signal cross-platform capability in progress (not yet complete)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- cleandeep skill ready for Linux/WSL2 environments — Phases 2, 4, 5, 6, 11, 14 gracefully skip; remaining phases run cross-platform (may produce empty output on Linux until Phase 2 of roadmap adds Linux commands)
- Pattern established for remaining skills needing OS detection treatment (see plans 01-03 onward)

---
*Phase: 01-os-detection-config*
*Completed: 2026-04-17*
