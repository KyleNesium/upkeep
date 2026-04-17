---
phase: 02-linux-cleanup
plan: 04
subsystem: skills
tags: [linux, bash, cleanquick, apt, dnf, pacman, cache-cleanup, cross-platform]

# Dependency graph
requires:
  - phase: 01-os-detection-config
    provides: OS detection snippet (OS_TYPE / PKG_MGR variables) and allowed-tools slots
provides:
  - cleanquick Phase 2 runs distro-routed lightweight pkg cache cleanup on Linux/WSL2
  - cleanquick Phase 3 includes age-based ~/.cache sweep (mtime +30) for Linux/WSL2
affects: [02-linux-cleanup, cleandeep, cleanquick]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Branching OS guard: linux/wsl2 branch before elif != macos fallback"
    - "Quick-mode scope enforcement: lighter subcommands (autoclean not clean, dnf clean packages not clean all) with explicit prose banning heavier ops"
    - "Age-based cache sweep: find -mtime +30 with mindepth/maxdepth bounds and warn-list for sensitive dirs"

key-files:
  created: []
  modified:
    - upkeep/skills/cleanquick/SKILL.md

key-decisions:
  - "Phase 2 quick mode uses apt-get autoclean (not apt-get clean) — removes obsolete debs only, safer for monthly cadence"
  - "Phase 2 dnf uses dnf clean packages (not dnf clean all) — preserves metadata, lighter footprint"
  - "Phase 3 mtime +30 scope: mindepth 1 maxdepth 2 to avoid descending into hot subcache paths"
  - "Warn-list (mesa_shader_cache, fontconfig, nvidia) surfaced in approval gate prose so AI can re-prompt if user selects them"
  - "No autoremove, no journal vacuum, no snap/flatpak in quick mode — all deferred to cleandeep with explicit routing message"

patterns-established:
  - "Quick-mode approval gate pattern: show dry-run/preview, prompt yes/no, execute only on yes"
  - "Scope boundary documentation: prose explicitly names what is NOT done and where to go instead (/upkeep:cleandeep)"

requirements-completed: [LNX-07]

# Metrics
duration: 2min
completed: 2026-04-17
---

# Phase 02 Plan 04: cleanquick Linux Phase 2 and Phase 3 Summary

**cleanquick gains Linux support: distro-routed apt/dnf/pacman cache cleanup in Phase 2 and mtime-based ~/.cache age sweep in Phase 3, both approval-gated and scoped to avoid autoremove, journal, snap, and flatpak**

## Performance

- **Duration:** 2 min
- **Started:** 2026-04-17T12:27:19Z
- **Completed:** 2026-04-17T12:29:06Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Phase 2 replaces the macOS-only skip guard with a full Linux/WSL2 branch: shows cache size + dry-run preview per distro (apt-get autoclean, dnf clean packages, pacman -Sc), approval-gates the actual run, and falls through to the existing Homebrew path on macOS unchanged
- Phase 3 gains Step 3: Linux/WSL2 age-based sweep that finds ~/.cache subdirs older than 30 days, reports sizes, removes with approval, and warns on mesa_shader_cache / fontconfig / nvidia entries
- Quick-mode scope boundary enforced: no autoremove, no journal vacuum, no snap/flatpak — prose explicitly defers all heavier ops to /upkeep:cleandeep

## Task Commits

Each task was committed atomically:

1. **Task 1: Replace Phase 2 skip guard with Linux lightweight cache cleanup** - `f2ee3bf` (feat)
2. **Task 2: Add Linux ~/.cache age-based sweep to Phase 3** - `f2ee3bf` (feat)

(Both tasks modified the same file and were verified together before committing as one atomic unit.)

**Plan metadata:** _(docs commit hash recorded after state update)_

## Files Created/Modified

- `upkeep/skills/cleanquick/SKILL.md` — Phase 2 Linux pkg-cache branch + Phase 3 Step 3 age sweep added; macOS Homebrew flow and cross-platform Step 2 scan unchanged

## Decisions Made

- `apt-get autoclean` chosen over `apt-get clean` for quick mode: removes only obsolete .debs (those superseded by newer versions) rather than all cached packages — lower risk, appropriate for monthly cadence
- `dnf clean packages` chosen over `dnf clean all`: removes cached .rpm files but preserves metadata, lighter footprint for quick mode
- `find -mtime +30 -mindepth 1 -maxdepth 2` bounds: mindepth avoids touching ~/.cache itself, maxdepth 2 avoids descending into hot sub-paths that may have recent writes within an old top-level dir
- Warn-list (mesa_shader_cache, fontconfig, nvidia) embedded in approval gate instruction so the AI re-confirms if user selects them before removing

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None. The grep-based acceptance criteria flagged `apt-get autoremove`, `dnf autoremove`, and `journalctl` as present — verified these appear only in prohibition prose ("Quick mode never runs...") and the pre-existing allowed-tools frontmatter, which is correct and expected.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- cleanquick now handles Linux/WSL2 for Phase 2 (pkg cache) and Phase 3 (user cache)
- Phase 5 (cleanquick Linux Trash via ~/.local/share/Trash) can now proceed — all prior quick phases have Linux coverage
- macOS regression risk: zero — existing Homebrew commands and Library/Caches scan unchanged

---
*Phase: 02-linux-cleanup*
*Completed: 2026-04-17*
