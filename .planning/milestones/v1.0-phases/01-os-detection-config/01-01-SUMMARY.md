---
phase: 01-os-detection-config
plan: "01"
subsystem: upkeep-router-skill
tags: [os-detection, cross-platform, skill, macos-guard]
dependency_graph:
  requires: []
  provides: [OS_TYPE, OS_DISTRO, PKG_MGR, macos-phase-guards, linux-allowed-tools]
  affects: [upkeep/skills/upkeep/SKILL.md]
tech_stack:
  added: []
  patterns: [os-detection-snippet, macos-guard-pattern, canonical-bash-block]
key_files:
  created: []
  modified:
    - upkeep/skills/upkeep/SKILL.md
decisions:
  - "OS detection snippet inserted as '## Environment Detection' section (not inline per-phase)"
  - "Version bumped to 1.1.0-dev to mark in-progress cross-platform work"
  - "mas/softwareupdate wrapped in OS_TYPE=macos conditional in Update Mode Step 2"
  - "Phase 15 (pipx) not guarded — cross-platform by design"
metrics:
  duration_minutes: 2
  completed_date: "2026-04-17"
  tasks_completed: 3
  tasks_total: 3
  files_modified: 1
---

# Phase 1 Plan 1: OS Detection & Config (Router Skill) Summary

Updated `upkeep/skills/upkeep/SKILL.md` with OS detection, Linux allowed-tools, and macOS-only phase guards — enabling graceful cross-platform execution without breaking existing macOS behavior.

## What Was Built

### Task 1: Extend allowed-tools frontmatter with Linux commands

Added 11 new `allowed-tools` entries to the SKILL.md frontmatter (baseline was 60, now 71):

- **OS detection group** (4 entries): `uname`, `lsb_release`, `lsblk`, `cat` — placed after `/usr/libexec/PlistBuddy` with comment `# OS detection (cross-platform)`
- **Linux system tools** (2 entries): `systemctl`, `journalctl` — new section at end of frontmatter
- **Linux package managers** (5 entries): `apt`, `dnf`, `pacman`, `snap`, `flatpak` — new section at end of frontmatter
- Version bumped from `1.0.6` to `1.1.0-dev`

### Task 2: Insert OS detection snippet

Added `## Environment Detection` section between the intro sentence and `## Mode Selection`. The section contains:
- Canonical bash block: uname-based kernel detection, WSL2 check via kernel release string containing "microsoft", `/etc/os-release` + `lsb_release` distro probing, `PKG_MGR` assignment per distro family
- `export OS_TYPE OS_DISTRO PKG_MGR` so all phases share the variables
- Echo line prints detected environment visibly at session start
- Prose note: unknown OS_TYPE skips non-cross-platform phases gracefully

### Task 3: Guard macOS-only phases and Update Mode mas/softwareupdate

Added OS guard blocks to 6 phases:
- Phase 2 (Homebrew Audit) — before existing `command -v brew` check
- Phase 4 (Orphaned Application Data) — at top of phase body
- Phase 5 (LaunchAgents) — at top of phase body
- Phase 6 (Xcode & Developer Tools) — before existing `command -v xcode-select` check
- Phase 11 (Electron App Caches) — at top of phase body
- Phase 14 (iPhone / iOS Backups) — at top of phase body

Each guard uses the pattern:
```bash
if [ "$OS_TYPE" != "macos" ]; then
  echo "Phase N: skipped (macOS only) — detected $OS_TYPE"
  # Stop this phase here. Continue to the next phase.
fi
```

Update Mode changes:
- Step 2: `mas outdated` and `softwareupdate -l` wrapped in `if [ "$OS_TYPE" = "macos" ]` conditional with `else echo "mas + softwareupdate: skipped (macOS only)"` branch
- Step 5: prose note added before upgrade table instructing Claude to skip `mas` and `macOS` rows on Linux/WSL2 with `↷ skipped (macOS only)` in final report

Not guarded (cross-platform): Phases 1, 3, 7, 8, 9, 10, 12, 13, 15

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | `cbc8d03` | feat(01-01): extend allowed-tools frontmatter with Linux commands |
| 2 | `b422591` | feat(01-01): insert OS detection snippet before Mode Selection |
| 3 | `237bf77` | feat(01-01): guard macOS-only phases and Update Mode mas/softwareupdate |

## Verification Results

All automated verify commands passed:

```
grep -qE "^\s*- Bash\(uname \*\)$" ... && echo OK  →  OK
grep -q "^## Environment Detection$" ... && echo OK  →  OK
test $(grep -c 'Phase .*: skipped (macOS only)') -ge 6  →  6 guards confirmed
grep -q 'mas + softwareupdate: skipped (macOS only)'  →  PASS
grep -c "^  - Bash(" → 71  (baseline 60 + 11 new)
No duplicate phase headings: 0
```

## Deviations from Plan

None — plan executed exactly as written.

## Requirements Satisfied

- OS-01: OS detection at phase entry (Environment Detection section runs first)
- OS-02: WSL2 distinguished from plain Linux via kernel release "microsoft" check
- OS-03: macOS-only phases (2, 4, 5, 6, 11, 14) guarded with skip notes
- OS-04: macOS behavior unchanged — guards evaluate false on Darwin, existing content runs
- CFG-01: Linux commands added to allowed-tools (uname, lsb_release, lsblk, cat, systemctl, journalctl, apt, dnf, pacman, snap, flatpak)

## Self-Check: PASSED

- `/Users/kyle/workspace/Github/KyleNesium/upkeep/upkeep/skills/upkeep/SKILL.md` — exists, 71 Bash entries, version 1.1.0-dev
- Commit `cbc8d03` — confirmed in git log
- Commit `b422591` — confirmed in git log
- Commit `237bf77` — confirmed in git log
