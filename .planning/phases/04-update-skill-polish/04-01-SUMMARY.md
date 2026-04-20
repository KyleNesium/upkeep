---
phase: 04-update-skill-polish
plan: 01
subsystem: skills
tags: [bash, linux, apt, dnf, pacman, snap, flatpak, cross-platform]

# Dependency graph
requires:
  - phase: 03-wsl2-support
    provides: Windows package manager audit block and WSL2 guard patterns
  - phase: 01-os-detection-config
    provides: OS detection block setting $OS_TYPE, $OS_DISTRO, $PKG_MGR
provides:
  - Linux apt/dnf/pacman upgrade section in Step 5 with per-manager dry-run preview and approval gates
  - snap refresh section gated by command -v snap with list and apply blocks
  - flatpak update section gated by command -v flatpak with list and apply blocks
  - Per-tool mas/softwareupdate skip notes on Linux/WSL2 in Step 2
  - Step 6 report rows for apt, snap, and flatpak
affects: [04-update-skill-polish]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - case $PKG_MGR dispatch inside $OS_TYPE linux/wsl2 gate for package manager routing
    - command -v guard for optional tools (snap, flatpak) — consistent with Phase 3 WSL2 pattern
    - sudo upgrade commands surfaced only in Manual Steps prose blockquotes — never in executable bash fences

key-files:
  created: []
  modified:
    - upkeep/skills/update/SKILL.md

key-decisions:
  - "apt upgrade: dry-run via apt-get upgrade --dry-run + grep ^Inst count, not apt list --upgradable — matches plan specifics"
  - "dnf upgrade: dnf check-update (not dnf upgrade --assumeno) per plan exact content"
  - "pacman upgrade: pacman -Qu (pending upgrades list) for dry-run preview — clean output"
  - "sudo upgrade commands for all Linux package managers placed in prose blockquote only — never inside bash fences"
  - "snap/flatpak gated by command -v (not $OS_TYPE) because they can theoretically exist on macOS via third-party"

patterns-established:
  - "Linux upgrade gate pattern: if [ \"$OS_TYPE\" = \"linux\" ] || [ \"$OS_TYPE\" = \"wsl2\" ] wrapping case $PKG_MGR dispatch"
  - "Optional tool guard: command -v <tool> >/dev/null 2>&1 before list and apply blocks separately (2 guards per tool)"
  - "Manual Steps prose for sudo: use > blockquote after executable bash fence, never inline sudo in fence"

requirements-completed: [UPD-01, UPD-02, UPD-03, UPD-04]

# Metrics
duration: 2min
completed: 2026-04-17
---

# Phase 04 Plan 01: Update Skill Polish — Linux Upgrade Paths Summary

**apt/dnf/pacman upgrade section, snap refresh, and flatpak update added to Step 5 with per-manager approval gates; mas/softwareupdate each show independent visible skip lines on Linux/WSL2**

## Performance

- **Duration:** 2 min
- **Started:** 2026-04-17T16:03:37Z
- **Completed:** 2026-04-17T16:05:48Z
- **Tasks:** 3
- **Files modified:** 1

## Accomplishments

- Step 2 now shows `echo "mas: skipped (macOS only)"` and `echo "softwareupdate: skipped (macOS only)"` as separate lines (not combined) on Linux/WSL2
- Step 5 Linux system packages section dispatches via `case "$PKG_MGR" in` for apt/dnf/pacman with dry-run previews, per-manager approval gates, and sudo upgrade guidance in Manual Steps prose
- Step 5 snap and flatpak sections added with `command -v` guards (2 guards each: list preview + apply), approval gates, and sudo fallback in prose only
- Step 6 final report template now includes apt, snap, and flatpak rows with guidance on when to show/omit each

## Task Commits

Each task was committed atomically:

1. **Task 1: Split mas/softwareupdate skip notes** - `28595d6` (feat)
2. **Task 2: Add Linux apt/dnf/pacman upgrade section** - `112eb7e` (feat)
3. **Task 3: Add snap refresh and flatpak update sections** - `089a058` (feat)

## Files Created/Modified

- `upkeep/skills/update/SKILL.md` - Added Linux upgrade paths to Step 5; split skip notes in Step 2; updated Step 6 report rows. Grew from 328 to 421 lines (+93 lines).

## File Offset Details

- **Lines 181-182** (Task 1): Per-tool echo lines replacing combined skip note
- **Lines 279-317** (Task 2): `### Linux system packages (apt / dnf / pacman)` block with case dispatch, approval gate, and Manual Steps prose
- **Lines 319-365** (Task 3): `### Snap packages (where installed)` and `### Flatpak applications (where installed)` blocks with command -v guards
- **Lines 397-401** (Task 3): Step 6 report rows for apt, snap, flatpak
- **Line 408** (Task 3): Appended Linux/WSL2 row guidance prose after Step 6 section

## Decisions Made

- apt dry-run uses `apt-get upgrade --dry-run | grep "^Inst"` with count — clear package listing
- dnf dry-run uses `dnf check-update` — lighter than `dnf upgrade --assumeno` for read-only preview
- pacman dry-run uses `pacman -Qu` — lists pending upgrades cleanly
- sudo commands for all Linux managers placed exclusively in `> blockquote` prose, never inside bash fences — maintains the skill's "Never run sudo" rule
- snap/flatpak gated by `command -v` rather than `$OS_TYPE` per plan guidance (third-party macOS installs are possible)

## Deviations from Plan

None - plan executed exactly as written. All verbatim content blocks from the plan were inserted as-is.

## Issues Encountered

None.

## Verification Checks (All Passed)

1. `grep -c "skipped (macOS only)"` → **5** (Step 2 mas, Step 2 softwareupdate, Step 3 prose, Step 5 intro, Step 6 prose)
2. `grep -nE '^  echo "(mas|softwareupdate): skipped'` → **2 matches** (exactly the two per-tool lines)
3. `grep -c 'case "$PKG_MGR" in'` → **1** (Linux dispatch)
4. `grep -cE 'command -v (snap|flatpak)'` → **4** (2 snap guards + 2 flatpak guards)
5. No `sudo (apt-get|dnf|pacman|snap|flatpak)` at line start inside bash fences → **0 matches** (PASS)
6. `grep -c 'brew upgrade'` → **1** (macOS regression check PASS); `grep -c 'mas outdated 2>/dev/null'` → **1** (PASS)
7. `head -1` → `---` (frontmatter intact)

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 04-01 complete. update/SKILL.md is now fully cross-platform: Linux apt/dnf/pacman + snap + flatpak upgrade paths live alongside macOS paths with zero regression.
- Plan 04-02 (router/README polish — CFG-02, CFG-03) appears already committed from a prior session (`fac1c42`, `85d14d8`). STATE.md should confirm whether 04-02 also needs a SUMMARY.

---
*Phase: 04-update-skill-polish*
*Completed: 2026-04-17*
