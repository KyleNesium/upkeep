---
phase: 04-update-skill-polish
plan: 02
subsystem: documentation
tags: [cross-platform, linux, wsl2, macos, skill-description, readme, badges]

# Dependency graph
requires:
  - phase: 04-01
    provides: Linux upgrade paths in update/SKILL.md (UPD-01 through UPD-04)
  - phase: 03-wsl2-support
    provides: WSL2 OS detection, banner, Windows package manager audit
  - phase: 02-linux-cleanup
    provides: Linux cleanup phases for apt/dnf/pacman, snap, flatpak, journalctl
provides:
  - Cross-platform SKILL.md router: description + H1 + intro reflect macOS/Linux/WSL2
  - README with Linux and WSL2 badges, updated Prerequisites section, Platform Support table, annotated Cleanup Categories table
affects: [future-phases, users-first-impression, plugin-marketplace-discovery]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Platform Support table: enumerate each platform with its package managers and platform-specific phases"
    - "Cleanup Categories table: Platform column tags each phase as 'all' or 'macOS' for at-a-glance cross-platform visibility"

key-files:
  created: []
  modified:
    - upkeep/skills/upkeep/SKILL.md
    - README.md

key-decisions:
  - "Frontmatter description block lists distros explicitly (Debian/Ubuntu, Fedora/RHEL, Arch) rather than just 'Linux' for discoverability"
  - "WSL2 badge links to learn.microsoft.com/windows/wsl/ (official docs) rather than a generic URL"
  - "Linux badge color FCC624 matches the official Linux/kernel yellow for brand recognition"
  - "Platform Support section placed between Prerequisites and Install — contextually after prereqs, before first-use instructions"
  - "Cleanup Categories table uses 'all' not 'cross-platform' for column brevity"

patterns-established:
  - "Platform column in feature tables: 'all' = everywhere, platform name = restricted"
  - "Platform Support section as a standalone section separate from Prerequisites"

requirements-completed: [CFG-02, CFG-03]

# Metrics
duration: 3min
completed: 2026-04-17
---

# Phase 4 Plan 02: Update Skill Polish — Documentation Summary

**Cross-platform SKILL.md router + README updated: Linux/WSL2 badges, Platform Support table, Prerequisites overhaul, and Cleanup Categories platform annotation**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-04-17T16:03:41Z
- **Completed:** 2026-04-17T16:07:03Z
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments

- Rewrote upkeep/skills/upkeep/SKILL.md description frontmatter and intro paragraph to declare macOS 14+, Linux (Debian/Ubuntu, Fedora/RHEL, Arch), and WSL2 support with distro-specific package manager detail
- Updated README.md subtitle, added Linux and WSL2 shields.io badges (preserving all existing badges byte-for-byte), and restructured Prerequisites into three subsections (Supported platforms / Required / Optional)
- Added new ## Platform Support section to README.md with per-platform package manager table and OS detection explanation; annotated all 15 rows of the Cleanup Categories table with a Platform column (macOS-only vs all)

## Task Commits

Each task was committed atomically:

1. **Task 1: CFG-02 — Rewrite upkeep router SKILL.md for cross-platform** - `fac1c42` (feat)
2. **Task 2: CFG-03 — Update README subtitle, badges, Prerequisites** - `85d14d8` (feat)
3. **Task 3: CFG-03 — Add Platform Support section and annotate Cleanup Categories** - `66c591c` (feat)
4. **Test Coverage update (deviation Rule 2)** - `b98037a` (docs)

**Plan metadata:** _(created after SUMMARY.md)_

## Files Created/Modified

- `upkeep/skills/upkeep/SKILL.md` — description frontmatter block replaced with cross-platform content; H1 updated from "macOS System Cleanup" to "Cross-Platform System Cleanup"; intro paragraph updated from macOS specialist to cross-platform specialist
- `README.md` — subtitle, tagline, badge row, Prerequisites section, new Platform Support section, Cleanup Categories table Platform column, Test Coverage line

## Exact Lines Modified

### upkeep/skills/upkeep/SKILL.md

| Edit | What changed |
|------|-------------|
| description frontmatter (lines 5-14) | Replaced macOS-only description with cross-platform description enumerating apt/dnf/pacman, ~/.cache, systemd journal, snap/flatpak, /mnt/c WSL2 bridge; updated use-when triggers to include linux/wsl2 cleanup phrases |
| H1 heading (was line 113) | `# /upkeep — macOS System Cleanup` → `# /upkeep — Cross-Platform System Cleanup` |
| Intro paragraph (was lines 115-116) | "You are a macOS system cleanup specialist..." → "You are a cross-platform system cleanup specialist supporting macOS 14+, Linux (Debian/Ubuntu, Fedora/RHEL, Arch), and WSL2..." with environment detection routing note |

### README.md

| Edit | What changed |
|------|-------------|
| Line 5 subtitle | `**macOS system cleanup and updater...` → `**Cross-platform system cleanup and updater...` |
| Line 7 tagline | Added Linux distros and WSL2, expanded package manager list to include apt/dnf/pacman/snap/flatpak |
| Lines 10-11 (inserted) | Added Linux badge (Debian\|Fedora\|Arch, FCC624 yellow) and WSL2 badge (supported, 4EAA25 green) |
| Lines 54-70 Prerequisites | Restructured into ### Supported platforms / ### Required / ### Optional subsections |
| Lines 74-91 (inserted) | New ## Platform Support section with 5-row platform table and detection explanation |
| Line 164 table header | Added `Platform` column between `Category` and `Deep` |
| Lines 165-180 table rows | Added Platform cell to all 15 rows: macOS-only (2,4,5,6,11,14) tagged `macOS`; cross-platform (1,3,7,8,9,10,12,13,15) tagged `all` |
| Line 182 (inserted) | Explanatory paragraph after table with [Platform Support](#platform-support) internal link |
| Line 348 Test Coverage | Updated "on macOS" → "across macOS, Linux, and WSL2" |

## Verification Results

All final verification checks passed:

1. `grep -c 'WSL2' upkeep/skills/upkeep/SKILL.md` → 7 (≥2 required)
2. `grep -c 'WSL2' README.md` → 7 (≥6 required)
3. `grep -c 'Debian/Ubuntu' upkeep/skills/upkeep/SKILL.md` → 2 (≥1 required)
4. `grep -c 'Debian/Ubuntu' README.md` → 2 (≥2 required)
5. `grep -c '^## Platform Support' README.md` → 1 (exactly 1 required)
6. `grep -c '^## Prerequisites' README.md` → 1 (exactly 1 required)
7. `grep -c '### Supported platforms' README.md` → 1 (exactly 1 required)
8. `head -1 upkeep/skills/upkeep/SKILL.md` → `---` (valid YAML frontmatter start)
9. `head -1 README.md` → `<div align="center">` (correct)
10. `grep 'name: upkeep' upkeep/skills/upkeep/SKILL.md` → match (unchanged)
11. `grep -c 'License: MIT' README.md` → 1 (badge preserved)
12. Platform Support section line 74 < Install section line 92 (correct ordering)
13. All 15 Cleanup Categories rows have correct Platform values (verified individually)

## Decisions Made

- Frontmatter description block lists distros explicitly (Debian/Ubuntu, Fedora/RHEL, Arch) rather than just "Linux" for better Claude Code skill discovery
- WSL2 badge links to official Microsoft Learn docs (learn.microsoft.com/windows/wsl/)
- Linux badge uses FCC624 (Linux kernel yellow) for recognizable brand color
- Platform Support section placed between Prerequisites and Install for logical flow: users understand platform before install
- Table uses `all` not `cross-platform` for column brevity and scan-friendliness

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Updated Test Coverage section to reflect cross-platform testing**
- **Found during:** Post-task review (global CLAUDE.md rule: "Keep Test Coverage section current")
- **Issue:** README Test Coverage still said "Tested via live invocation against all five entry points on macOS" after the README was updated to claim cross-platform support
- **Fix:** Updated the description to "across macOS, Linux, and WSL2"
- **Files modified:** README.md
- **Verification:** Line 348 updated
- **Committed in:** b98037a (separate docs commit)

---

**Total deviations:** 1 auto-fixed (Rule 2 — missing critical consistency update)
**Impact on plan:** Minor text correction for internal consistency. No scope creep.

## Issues Encountered

None — all three tasks executed cleanly on first attempt.

## Next Phase Readiness

- CFG-02 and CFG-03 requirements are complete
- Phase 04 plan 02 is the final plan in the project roadmap
- All four phases of the cross-platform effort are now complete: OS detection (01), Linux cleanup phases (02), WSL2 support (03), update skill + documentation polish (04)
- Repository is ready for a v1.1.0 release bump when version strings are updated

---
*Phase: 04-update-skill-polish*
*Completed: 2026-04-17*
