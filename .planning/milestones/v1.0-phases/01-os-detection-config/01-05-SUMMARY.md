---
phase: 01-os-detection-config
plan: "05"
subsystem: skills
tags: [bash, os-detection, cross-platform, macos, linux, wsl2, update-skill]

# Dependency graph
requires:
  - phase: 01-os-detection-config
    provides: canonical OS detection snippet established in plans 01-01 through 01-04
provides:
  - update skill with OS detection before Step 1
  - mas and softwareupdate guarded on OS_TYPE=macos in Step 2
  - prose guidance in Step 3, Step 5, Step 6 for skipping macOS-only rows on Linux/WSL2
  - Linux allowed-tools in update skill frontmatter (Phase 4 slots)
affects:
  - phase 4 (Linux package manager upgrade paths — apt/dnf/pacman)
  - any plan that reads the update skill's allowed-tools

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "OS gate pattern: if [ $OS_TYPE = macos ] wraps mas + softwareupdate in Step 2 bash block"
    - "Skip-prose pattern: prose additions in Steps 3/5/6 instruct skill to label macOS-only rows as 'skipped (macOS only)'"

key-files:
  created: []
  modified:
    - upkeep/skills/update/SKILL.md

key-decisions:
  - "Only mas and softwareupdate are macOS-only in the update skill — brew, npm, pipx, gem, rustup, cargo, bun, deno, mise, uv remain unconditional (cross-platform)"
  - "mas and macOS rows stay in the Step 5 upgrade table — they are not deleted, only skipped at runtime based on OS_TYPE"
  - "Linux allowed-tools slots added now (apt, dnf, pacman, snap, flatpak, systemctl, journalctl) so Phase 4 can add upgrade commands without re-editing frontmatter"

patterns-established:
  - "Step 2 bash block: macOS-only commands wrapped in if/else with echo skip note for non-macOS"
  - "Steps 3/5/6: prose additions instruct skill to omit or label macOS-only rows on Linux/WSL2"

requirements-completed: [OS-01, OS-02, OS-03, OS-04, CFG-01]

# Metrics
duration: 15min
completed: 2026-04-17
---

# Phase 1 Plan 05: OS Detection & Config (Update Skill) Summary

**Update skill gains OS detection + `[ $OS_TYPE = "macos" ]` gate around mas/softwareupdate in Step 2, skip-prose in Steps 3/5/6, and Linux allowed-tools slots for Phase 4**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-04-17
- **Completed:** 2026-04-17
- **Tasks:** 3
- **Files modified:** 1

## Accomplishments
- Extended allowed-tools frontmatter with 11 Linux commands (uname, lsb_release, lsblk, cat, systemctl, journalctl, apt, dnf, pacman, snap, flatpak) and bumped version to 1.1.0-dev
- Inserted canonical `## Environment Detection` section before Step 1, setting OS_TYPE/OS_DISTRO/PKG_MGR and printing detected environment on startup
- Wrapped `mas outdated` and `softwareupdate -l` in `if [ "$OS_TYPE" = "macos" ]` in Step 2 so they never execute on Linux/WSL2

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend update allowed-tools frontmatter with Linux commands** - `440ddc8` (feat)
2. **Task 2: Insert OS detection snippet at top of update instruction body** - `e907a18` (feat)
3. **Task 3: Gate mas and softwareupdate on $OS_TYPE in Step 2, Step 3, Step 5, Step 6** - `b42f941` (feat)

## Files Created/Modified
- `upkeep/skills/update/SKILL.md` - OS detection, mas/softwareupdate guards, Linux allowed-tools, version bump

## Decisions Made
- Only mas and softwareupdate need OS guards in update skill — all other package managers (brew, npm, pipx, gem, rustup, cargo, bun, deno, mise, uv) are cross-platform and remain unconditional
- Kept mas/macOS rows in the Step 5 upgrade table intact; skip is enforced via runtime prose, not table deletion, so macOS users see the same table structure
- Phase 4 Linux upgrade-command slots added to allowed-tools now to avoid future frontmatter re-edits

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- All 5 update skill tasks complete; Phase 1 (OS Detection & Config) is now fully executed across all skills
- Phase 4 can add Linux package manager upgrade commands to the update skill using the pre-populated allowed-tools slots

---
*Phase: 01-os-detection-config*
*Completed: 2026-04-17*
