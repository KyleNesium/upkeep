---
phase: 06-umbrella-update-parity
plan: 01
subsystem: upkeep/skills/upkeep/SKILL.md
tags: [linux, wsl2, update-mode, apt, snap, flatpak, winget, gap-closure]
dependency_graph:
  requires: [05-01-PLAN.md]
  provides: [Update Mode Linux parity in umbrella router]
  affects: [upkeep/skills/upkeep/SKILL.md]
tech_stack:
  patterns: [OS-type dispatch, PKG_MGR case dispatch, command -v guards, audit-only WSL2 detection]
key_files:
  modified:
    - upkeep/skills/upkeep/SKILL.md
decisions:
  - "Tasks 1+2 pre-existed as uncommitted working tree changes; committed together before executing Task 3"
  - "Linux $PKG_MGR sudo upgrade surfaced as Manual Steps prose only — never run from skill (matches update/SKILL.md pattern)"
  - "snap/flatpak gated by command -v (not $OS_TYPE) to handle rare non-Linux installs"
  - "macOS tool table (brew/npm/pipx/gems/rustup/cargo/uv/bun/deno/mise/mas) left unchanged — no regression"
metrics:
  duration_seconds: 87
  completed_date: "2026-04-19"
  tasks_completed: 3
  files_modified: 1
requirements_closed: [UPD-01, UPD-02, UPD-03, WSL-04]
---

# Phase 06 Plan 01: Umbrella Update Mode Linux Parity Summary

**One-liner:** Ported Linux $PKG_MGR dispatch (apt/dnf/pacman), snap refresh, flatpak update, and WSL2 Windows pkg detection (winget/scoop/choco audit-only) from update/SKILL.md into the umbrella upkeep/skills/upkeep/SKILL.md Update Mode Steps 2/3/5/6.

## What Was Built

MISS-5 closed. The umbrella router's Update Mode was macOS-centric only. This plan brought full Linux/WSL2 parity:

- **Step 2:** WSL2 Windows package manager detection (winget/scoop/choco) via /mnt/c guard — audit-only, no upgrades
- **Step 3:** Overview Table extended with `── Windows Packages (WSL2 only — audit only) ──` group; Linux annotation for mas/macOS rows
- **Step 5:** Full Linux-aware preamble + three new sections before existing macOS tool table:
  - `### Linux system packages (apt / dnf / pacman)` — $PKG_MGR case dispatch, dry-run preview, approval gate, Manual Steps sudo
  - `### Snap packages (where installed)` — command -v guard, snap refresh --list preview, snap refresh apply
  - `### Flatpak applications (where installed)` — command -v guard, flatpak remote-ls --updates preview, flatpak update -y apply
  - `### macOS and cross-platform package managers` heading before existing table (table itself unchanged)
- **Step 6:** Final Report template extended with apt/snap/flatpak rows

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1+2  | 8b5642b | feat(06-01): Task 1+2 — WSL2 Windows pkg detection + overview table update |
| 3    | b7b52d2 | feat(06-01): Task 3 — add Linux PKG_MGR, snap, flatpak to Update Mode Step 5+6 |

## Verification Results

| Check | Result |
|-------|--------|
| `winget list 2>/dev/null` in Step 2 | PASS |
| `apt-get upgrade --dry-run` in Step 5 | PASS |
| `snap refresh --list` in Step 5 | PASS |
| `flatpak update -y` in Step 5 | PASS |
| `brew upgrade` still present (macOS unchanged) | PASS |
| Step 6 `flatpak ✓ updated N apps` row | PASS |
| winget/scoop/choco count ≥ 6 | PASS (18) |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - State] Tasks 1 and 2 were pre-existing uncommitted changes**
- **Found during:** Pre-task verification greps
- **Issue:** winget detection block and overview table Windows Packages group were already in the working tree but had no commit
- **Fix:** Committed both as a combined Task 1+2 commit before executing Task 3
- **Files modified:** upkeep/skills/upkeep/SKILL.md
- **Commit:** 8b5642b

## Self-Check: PASSED

- SUMMARY.md: FOUND
- Commit 8b5642b: FOUND
- Commit b7b52d2: FOUND
- All verification greps: PASSED
