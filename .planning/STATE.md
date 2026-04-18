---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: unknown
stopped_at: "Completed 05-01-PLAN.md (port Linux/WSL2 cleanup phases 1/2/9/16-18 to umbrella router)"
last_updated: "2026-04-18T21:48:12Z"
progress:
  total_phases: 5
  completed_phases: 4
  total_plans: 16
  completed_plans: 16
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-17)

**Core value:** Every upkeep command gracefully handles macOS, Linux, and WSL2 without errors
**Current focus:** Phase 04 — update-skill-polish

## Current Position

Phase: 05 (umbrella-cleanup-parity) — EXECUTING
Plan: 1 of 1 (completed)

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: -
- Total execution time: -

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**

- Last 5 plans: -
- Trend: -

*Updated after each plan completion*
| Phase 01 P03 | 8 | 2 tasks | 1 files |
| Phase 01-os-detection-config P02 | 13 | 3 tasks | 1 files |
| Phase 01 P01 | 2 | 3 tasks | 1 files |
| Phase 01 P05 | 15 | 3 tasks | 1 files |
| Phase 02 P01 | 2 | 2 tasks | 1 files |
| Phase 02-linux-cleanup P04 | 2 | 2 tasks | 1 files |
| Phase 02-linux-cleanup P05 | 3 | 3 tasks | 1 files |
| Phase 02-linux-cleanup P02 | 1 | 2 tasks | 1 files |
| Phase 02-linux-cleanup P03 | 1 | 2 tasks | 1 files |
| Phase 03-wsl2-support P01 | 8 | 3 tasks | 3 files |
| Phase 03 P02 | 2 | 4 tasks | 1 files |
| Phase 03-wsl2-support P03 | 3 | 3 tasks | 1 files |
| Phase 04-update-skill-polish P01 | 2 | 3 tasks | 1 files |
| Phase 04 P02 | 3 | 3 tasks | 2 files |
| Phase 05-umbrella-cleanup-parity P01 | 15 | 4 tasks | 1 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- OS detection at phase entry, not per-command (cleaner skill instructions; phases self-skip)
- Shared OS detection snippet per skill, not a shared file (skills are standalone in Claude Code)
- WSL2 = Linux + Windows extras (build on Linux support, then add Windows-side bonus)
- Linux distros: Debian/Ubuntu (apt), Fedora/RHEL (dnf), Arch (pacman) — others get graceful skips
- [Phase 01]: Phase 3 (Dev Tool Caches) left unguarded in cleanquick — ~/.cache/ works on Linux; macOS-specific paths return empty
- [Phase 01]: Phase 13 (Trash) left unguarded in cleanquick — Linux ~/.local/share/Trash handled in Phase 2 of roadmap
- [Phase 01]: audit allowed-tools declares Linux package managers (apt/dnf/pacman) proactively — read-only query context; avoids frontmatter re-edits when Phase 2 adds Linux commands
- [Phase 01]: audit OS guard placed BEFORE existing command -v checks to prevent brew/xcode-select invocation on Linux
- [Phase 01-os-detection-config]: cleandeep guards placed BEFORE command -v checks so macOS falls through to existing tool-availability checks unchanged
- [Phase 01]: Only mas and softwareupdate need OS guards in update skill — brew, npm, pipx, gem, rustup, cargo, bun, deno, mise, uv are cross-platform and remain unconditional
- [Phase 01-os-detection-config]: cleandeep version bumped to 1.1.0-dev to signal cross-platform work in progress
- [Phase 01]: Linux allowed-tools slots pre-populated in update skill so Phase 4 can add upgrade commands without re-editing frontmatter
- [Phase 01]: Version bumped to 1.1.0-dev in router skill to mark in-progress cross-platform work
- [Phase 02]: Phase 1 uses if/elif OS branching so macOS and Linux run separate commands
- [Phase 02]: stat fallback chain (stat -f %m || stat -c %Y || echo 0) makes update check cross-platform
- [Phase 02]: Phase 2 approval gate documented as markdown prose outside bash fence, not shell code
- [Phase 02-linux-cleanup]: cleanquick Phase 2 quick mode: apt-get autoclean (not clean), dnf clean packages (not clean all) — lighter footprint for monthly cadence, no autoremove
- [Phase 02-linux-cleanup]: cleanquick Phase 3 Step 3: find -mtime +30 -mindepth 1 -maxdepth 2 bounds to avoid ~/.cache itself and hot sub-paths; warn-list for mesa_shader_cache/fontconfig/nvidia
- [Phase 02-linux-cleanup]: Phase 9 macOS Library/Logs body wrapped in OS guard to prevent Linux noise
- [Phase 02-linux-cleanup]: stat -c %Y fallback added to update-check for Linux stat compatibility
- [Phase 02-linux-cleanup]: audit Phase 14 heading renamed to cover iOS Backups (macOS) / Snap + Flatpak (Linux)
- [Phase 02-linux-cleanup]: Phase 3 Linux approval flow added as Step 3 after cross-platform Step 2; never blanket-wipe ~/.cache/, only named subdirs
- [Phase 02-linux-cleanup]: Warn list for slow-to-rebuild caches: mesa_shader_cache, fontconfig, nvidia
- [Phase 02-linux-cleanup]: User journal vacuumed at 200M; system journal sudo command surfaced as manual step only — never in executable fence
- [Phase 02-linux-cleanup]: Phase 16 placed after Phase 15 (pipx) and before Reporting — mirrors macOS optional-tool tail pattern
- [Phase 02-linux-cleanup]: sudo snap remove and sudo flatpak uninstall shown in fenced blocks with comment noting Manual Steps context, matching Phase 2/7/9 pattern throughout cleandeep skill
- [Phase 03-wsl2-support]: WSL2 banner is a separate bash fence after OS Detection block — not inlined — for clean diffs and visual distinction
- [Phase 03-wsl2-support]: Banner position: after OS Detection closing fence, before "If $OS_TYPE is unknown" paragraph — consistent across all five skills
- [Phase 03]: Phase 17/18 'Never use sudo' prose increases sudo grep count by 2 — these are policy statements, not commands
- [Phase 03]: /mnt/c accessibility guard placed as outer block so path stat errors never surface to user
- [Phase 03-wsl2-support]: Windows package managers detected via command -v + /mnt/c guard — never upgrade from WSL2 (UAC/permission implications)
- [Phase 03-wsl2-support]: Upgrade commands for winget/scoop/choco appear only in prose blockquote, never in executable bash fences
- [Phase 03-wsl2-support]: Step 5 upgrade table explicitly excludes winget/scoop/choco — audit-only note added before table for machine-checkable compliance
- [Phase 04-update-skill-polish]: apt/dnf/pacman upgrade via case $PKG_MGR dispatch inside linux/wsl2 gate; sudo commands surfaced as Manual Steps prose only
- [Phase 04-update-skill-polish]: snap/flatpak gated by command -v (not $OS_TYPE) to handle rare third-party macOS installs
- [Phase 04-update-skill-polish]: mas/softwareupdate each show independent skip lines — removed combined single echo line
- [Phase 04]: SKILL.md description lists distros explicitly (Debian/Ubuntu, Fedora/RHEL, Arch) for better skill discovery
- [Phase 04]: Platform Support section placed between Prerequisites and Install for logical user flow
- [Phase 04]: Cleanup Categories Platform column uses 'all'/'macOS' for scan-friendly brevity
- [Phase 05]: Umbrella router Phase 1 OS-branched — macOS gets diskutil+sw_vers, Linux/WSL2 gets df+os-release+kernel+PKG_MGR
- [Phase 05]: stat fallback chain extended to umbrella router (matches cleandeep/SKILL.md)
- [Phase 05]: Phase 2 approval gate prose uses "Linux/WSL2" qualifier to distinguish from macOS brew gate
- [Phase 05]: Phases 16–18 ported verbatim from cleandeep to umbrella — self-contained, no sub-skill calls

### Pending Todos

None yet.

### Blockers/Concerns

None yet.

## Session Continuity

Last session: 2026-04-18T21:48:12Z
Stopped at: Completed 05-01-PLAN.md (port Linux/WSL2 cleanup phases 1/2/9/16-18 to umbrella router)
Resume file: None
