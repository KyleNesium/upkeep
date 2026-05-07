---
phase: 05-umbrella-cleanup-parity
plan: 01
subsystem: upkeep/skills/upkeep
tags: [linux, wsl2, cleanup, gap-closure, phase-1, phase-2, phase-9, phase-16, phase-17, phase-18]
dependency-graph:
  requires: []
  provides: [umbrella-linux-cleanup-phases]
  affects: [upkeep/skills/upkeep/SKILL.md]
tech-stack:
  added: []
  patterns: [OS-branched bash guards, approval-gated Linux cleanup phases]
key-files:
  created: []
  modified:
    - upkeep/skills/upkeep/SKILL.md
decisions:
  - "Port content verbatim from cleandeep/SKILL.md — no new logic invented"
  - "Phase 2 approval gate prose updated to be Linux/WSL2-specific (not generic)"
  - "Phase 9 ~/Library/Logs commands wrapped in macOS guards (not deleted)"
metrics:
  duration: ~15 minutes
  completed: 2026-04-18T21:48:12Z
  tasks-completed: 4
  tasks-total: 4
  files-modified: 1
requirements-closed: [OS-01, LNX-01, LNX-02, LNX-04, LNX-05, LNX-06, WSL-02, WSL-03]
---

# Phase 05 Plan 01: Port Linux/WSL2 Cleanup Phases to Umbrella Router Summary

Port Linux/WSL2 cleanup content from cleandeep/SKILL.md into the umbrella upkeep/SKILL.md for phases 1, 2, 9, and new phases 16–18 — closing four gaps where Linux users got either empty output or "skipped (macOS only)" responses.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Fix Phase 1 Baseline — OS-branched info + cross-platform stat | c934853 | upkeep/skills/upkeep/SKILL.md |
| 2 | Fix Phase 2 — add Linux package cache cleanup body | 9ddcec7 | upkeep/skills/upkeep/SKILL.md |
| 3 | Fix Phase 9 — journalctl block + macOS guard on ~/Library/Logs | f0d1180 | upkeep/skills/upkeep/SKILL.md |
| 4 | Insert Phases 16/17/18 + Reporting table rows 16–18 | 8fb7769 | upkeep/skills/upkeep/SKILL.md |

## What Was Done

### Task 1 — Phase 1 Baseline
Replaced the unconditional 3-line bash block (`echo "=== macOS ===" && sw_vers`) with an `if/elif` OS-branched version:
- macOS branch: `diskutil info` + `sw_vers` + `brew --version`
- Linux/WSL2 branch: `df -h /` + `cat /etc/os-release` + `uname -r` + `$PKG_MGR` case dispatch

Also fixed the `stat -f %m` in the update check to `stat -f %m ... || stat -c %Y ... || echo 0` for cross-platform compatibility (macOS uses `-f %m`, Linux uses `-c %Y`).

### Task 2 — Phase 2
Replaced the bare `if [ "$OS_TYPE" != "macos" ]` skip guard with a Linux-first routing block containing:
- apt branch: cache size + clean dry-run + autoremove dry-run + old kernel image detection via `dpkg -l 'linux-image-*'`
- dnf branch: cache size + clean all preview + `dnf autoremove --assumeno` dry-run
- pacman branch: cache size + `-Sc` preview + `pacman -Qtdq` orphan detection
- `elif [ "$OS_TYPE" != "macos" ]` fallback for unsupported OS
- Approval gate prose with yes/skip-autoremove/no options
- macOS brew audit content unchanged beneath the Linux block

### Task 3 — Phase 9
- Inserted `journalctl --disk-usage` + `journalctl --user --disk-usage` block at top of Phase 9 inside a Linux/WSL2 guard
- Added journal vacuum approval gate: user journal to 200MB (no sudo), system journal 500MB surfaced under Manual Steps
- Wrapped `ls ~/Library/Logs/` in `if [ "$OS_TYPE" = "macos" ]` guard
- Wrapped both `find ~/Library/Logs` blocks in macOS guards

### Task 4 — Phases 16/17/18
- Inserted Phase 16 (Snap & Flatpak), Phase 17 (Windows Temp WSL2), Phase 18 (Windows npm/pip Cache) between Phase 15 and Update Mode — verbatim from cleandeep/SKILL.md
- Added rows 16, 17, 18 to Final Summary table in Reporting section
- Updated Quick phases annotation: `**Deep/Audit phases:** All 15.` → `All 15 (plus phases 16–18 on Linux/WSL2).`

## Verification Results

All 6 plan verification checks passed:
1. `grep -c 'Phase 16\|Phase 17\|Phase 18'` → 14 occurrences (minimum 6)
2. `cat /etc/os-release` present in Phase 1 Linux branch
3. `Phase 2: Linux package cache cleanup` present
4. `journalctl --disk-usage` present in Phase 9
5. `| 18| Windows npm/pip` present in Reporting table
6. `diskutil info` present (macOS Phase 1 regression check)

## Deviations from Plan

None — plan executed exactly as written. All 4 tasks ported content verbatim from cleandeep/SKILL.md with minor wording adjustments to the Phase 2 approval gate prose (changed "**Approval gate.**" to "**Approval gate (Linux/WSL2).**" and clarified the stop-and-continue text to reference brew commands rather than mdfind/launchctl).

## Success Criteria

- MISS-1 closed: Phase 1 OS-branched — macOS gets diskutil+sw_vers, Linux/WSL2 gets df+os-release+kernel+PKG_MGR
- MISS-2 closed: Phase 2 on Linux/WSL2 runs apt/dnf/pacman cache sweep with approval gate — not "skipped (macOS only)"
- MISS-3 closed: Phase 9 on Linux/WSL2 runs journalctl; ~/Library/Logs guarded to macOS
- MISS-4 closed: Phases 16/17/18 present between Phase 15 and Update Mode; Reporting table has rows 16–18
- No regression: macOS behavior unchanged in all 4 phases

## Self-Check: PASSED

- File exists: upkeep/skills/upkeep/SKILL.md — FOUND
- Commits c934853, 9ddcec7, f0d1180, 8fb7769 — all present in git log
