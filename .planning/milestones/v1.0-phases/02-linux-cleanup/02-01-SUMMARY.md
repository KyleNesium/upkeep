---
phase: 02-linux-cleanup
plan: 01
subsystem: skills
tags: [linux, wsl2, apt, dnf, pacman, cleandeep, bash, os-detection]

# Dependency graph
requires:
  - phase: 01-os-detection-config
    provides: OS detection snippet ($OS_TYPE/$OS_DISTRO/$PKG_MGR) already wired into cleandeep SKILL.md
provides:
  - Linux/WSL2 Phase 1 baseline reporting (df, os-release, kernel, package manager info)
  - Linux/WSL2 Phase 2 package cache cleanup with distro routing (apt/dnf/pacman)
  - Orphan package detection for all three distro families
  - Old kernel image listing for apt-based systems (LNX-06)
  - Approval gate with yes/skip-autoremove/no options
affects:
  - 02-linux-cleanup (subsequent plans can extend Phase 2 cleanup further)
  - cleandeep skill users on Linux/WSL2

# Tech tracking
tech-stack:
  added: []
  patterns:
    - OS_TYPE branching in skill bash blocks (if macos / elif linux or wsl2)
    - case PKG_MGR in for distro routing within Linux branches
    - GNU coreutils fallback: stat -c %Y alongside BSD stat -f %m

key-files:
  created: []
  modified:
    - upkeep/skills/cleandeep/SKILL.md

key-decisions:
  - "Phase 1 uses if/elif branching so macOS and Linux run completely separate commands — avoids command-not-found errors on either OS"
  - "stat fallback chain: BSD stat -f %m first, then GNU stat -c %Y, then echo 0 — update check works on both macOS and Linux without error"
  - "Phase 2 Linux branch ends with a comment gate so Claude does not fall through to the macOS Homebrew steps"
  - "Approval gate prose added as markdown outside bash fence — it becomes instructions to Claude, not shell code"

patterns-established:
  - "OS branch pattern: wrap existing macOS shell block in if [ OS_TYPE = macos ]; add elif linux/wsl2 branch immediately after"
  - "No sudo in bash fences: permission-error commands surfaced to user via ## Manual Steps prose only"

requirements-completed: [LNX-01, LNX-02, LNX-06]

# Metrics
duration: 2min
completed: 2026-04-17
---

# Phase 02 Plan 01: Linux cleandeep Phase 1 Baseline + Phase 2 Package Cache Summary

**Linux/WSL2 baseline reporting and approval-gated apt/dnf/pacman cache cleanup added to cleandeep Phase 1 and Phase 2**

## Performance

- **Duration:** 2 min
- **Started:** 2026-04-17T12:27:15Z
- **Completed:** 2026-04-17T12:29:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Phase 1 now branches on `$OS_TYPE`: macOS runs the original diskutil/sw_vers/brew block; Linux/WSL2 emits df, /etc/os-release, uname -r, and per-distro package manager info via a `case "$PKG_MGR" in` router
- Phase 2 replaces the blanket macOS-only skip guard with a full Linux branch that routes apt/dnf/pacman cache dry-run output and orphan listings, then gates actual cleanup on user approval (yes / skip-autoremove / no)
- apt branch includes explicit old kernel image listing via `dpkg -l 'linux-image-*'` (LNX-06); all three distros surface orphan packages before any removal
- GNU stat fallback added to the update-check block so `_LAST` resolves correctly on Linux (GNU `stat -c %Y`) and macOS (BSD `stat -f %m`)

## Task Commits

1. **Task 1: Add Linux baseline branch to Phase 1** - `10a3037` (feat)
2. **Task 2: Replace Phase 2 skip guard with Linux package cache body** - `f2ee3bf` (feat)

**Plan metadata:** _(to be committed as part of final docs commit)_

## Files Created/Modified

- `upkeep/skills/cleandeep/SKILL.md` — Phase 1 wrapped in OS branch + Linux baseline body; Phase 2 skip guard replaced with Linux package cache + orphan body; stat fallback added

## Decisions Made

- Phase 1 uses `if/elif` branching so macOS and Linux execute completely independent commands — no risk of `diskutil`/`sw_vers` running on Linux or `df`/`uname` being redundant on macOS
- `stat` fallback chain (`stat -f %m || stat -c %Y || echo 0`) keeps the update check cross-platform without changing its logic
- Phase 2 Linux branch ends with an explicit comment gate ("DO NOT run the macOS brew commands below") and the elif structure ensures macOS falls through only when `$OS_TYPE = macos`
- Approval gate documented as markdown prose outside the bash fence so it becomes Claude behavioral instructions, not shell code

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- LNX-01, LNX-02, LNX-06 complete — cleandeep now has full Linux Phase 1 and Phase 2 coverage
- Ready for Phase 02 Plan 02 (next Linux cleanup plan in the roadmap)
- macOS behavior is fully preserved; regression risk is zero

---
*Phase: 02-linux-cleanup*
*Completed: 2026-04-17*
