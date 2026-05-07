---
phase: 01-os-detection-config
plan: "04"
subsystem: audit
tags: [os-detection, bash, wsl2, linux, macos-guards, audit-skill]

# Dependency graph
requires:
  - phase: 01-os-detection-config
    provides: canonical OS detection snippet and macOS phase guard pattern
provides:
  - audit/SKILL.md with OS_TYPE detection (macos/linux/wsl2) before Phase 1
  - Six macOS phase guards in audit Phases 2, 4, 5, 6, 11, 14
  - Extended allowed-tools with 11 Linux commands (uname, lsb_release, lsblk, cat, systemctl, journalctl, apt, dnf, pacman, snap, flatpak)
affects: [02-linux-commands, future audit Linux enhancements]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "OS detection block: _KERNEL/uname pattern shared across all skills"
    - "macOS guard: OS_TYPE != 'macos' bail-out at phase top"
    - "allowed-tools extended with Linux tools for forward-compat"

key-files:
  created: []
  modified:
    - upkeep/skills/audit/SKILL.md

key-decisions:
  - "Audit mirrors cleandeep's 15-phase structure with same 6 macOS-only guards — must stay in lockstep"
  - "allowed-tools declares Linux package managers (apt/dnf/pacman) even though audit is read-only — enables Phase 2 roadmap additions without frontmatter re-edits"

patterns-established:
  - "Phase guard goes BEFORE existing tool-availability checks (e.g., command -v brew) not after"
  - "Guard prose line added after each fenced guard block for AI clarity"

requirements-completed: [OS-01, OS-02, OS-03, OS-04, CFG-01]

# Metrics
duration: 8min
completed: 2026-04-17
---

# Phase 1 Plan 04: OS Detection & Config — Audit Skill Summary

**audit/SKILL.md updated with OS detection (macos/linux/wsl2), 6 macOS phase guards, and 11 Linux allowed-tools entries — audit mirrors cleandeep's cross-platform surface area**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-04-17T00:00:00Z
- **Completed:** 2026-04-17T00:08:00Z
- **Tasks:** 3
- **Files modified:** 1

## Accomplishments

- Extended audit frontmatter with 11 Linux allowed-tools: uname, lsb_release, lsblk, cat (OS detection), systemctl, journalctl (Linux system tools), apt, dnf, pacman, snap, flatpak (Linux package managers)
- Inserted canonical `## Environment Detection` section before Phase 1, setting OS_TYPE/OS_DISTRO/PKG_MGR for the entire run
- Added OS_TYPE guards to Phases 2, 4, 5, 6, 11, 14 — each prints "Phase N: skipped (macOS only) — detected $OS_TYPE" and stops; Phases 1, 3, 7, 8, 9, 10, 12, 13, 15 remain unguarded

## Task Commits

1. **Task 1: Extend audit allowed-tools frontmatter with Linux commands** - `c90d950` (feat)
2. **Task 2: Insert OS detection snippet at top of audit instruction body** - `738bb29` (feat)
3. **Task 3: Guard macOS-only audit phases (2, 4, 5, 6, 11, 14)** - `361e3cc` (feat)

## Files Created/Modified

- `upkeep/skills/audit/SKILL.md` - Version bumped to 1.1.0-dev; 11 new allowed-tools entries; Environment Detection section; 6 macOS-only phase guards

## Decisions Made

- Audit allowed-tools declares Linux package managers proactively — they are read-only query tools in context of audit (`apt list --upgradable` etc.) and declaring them now avoids frontmatter re-edits when Phase 2 of roadmap adds Linux-specific commands
- Guard placed BEFORE existing `command -v brew` / `command -v xcode-select` checks to ensure Linux/WSL2 never even attempts brew invocation

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All 4 skills (cleandeep, cleanquick, update, audit) now have OS detection + macOS guards
- Phase 1 of roadmap complete: OS-01 through OS-04 and CFG-01 requirements satisfied
- Phase 2 of roadmap (Linux commands for each skill) can begin — allowed-tools already extended

---
*Phase: 01-os-detection-config*
*Completed: 2026-04-17*
