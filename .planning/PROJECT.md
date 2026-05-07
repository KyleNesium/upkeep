# upkeep

## What This Is

upkeep is a Claude Code skill plugin that does discovery-based system cleanup and package updates. It runs on macOS 14+, Linux (Debian/Ubuntu, Fedora/RHEL, Arch), and WSL2 — routing to the right cleanup phases and package managers based on detected environment.

## Core Value

Every upkeep command gracefully handles macOS, Linux, and WSL2 without errors, skipping unavailable phases rather than failing.

## Requirements

### Validated

- ✓ macOS deep clean (15-phase audit + cleanup) — v1.0.x (pre-milestone)
- ✓ Quick cleanup (caches + brew) — v1.0.x (pre-milestone)
- ✓ Audit mode (report only, no changes) — v1.0.x (pre-milestone)
- ✓ Update skill (git-based skills + package managers) — v1.0.x (pre-milestone)
- ✓ Discovery-based orphan detection — v1.0.x (pre-milestone)
- ✓ OS detection utility shared across all skills (macOS / Linux / WSL2) — v1.0
- ✓ Linux-specific cleanup phases (apt/dnf/pacman cache, journald, ~/.cache, snap, flatpak) — v1.0
- ✓ All SKILL.md allowed-tools updated with Linux commands — v1.0
- ✓ WSL2 detection and Windows-side cleanup via /mnt/c/ bridge — v1.0
- ✓ Linux package manager support in update skill (apt, dnf, pacman, snap, flatpak) — v1.0
- ✓ README, badges, and SKILL.md descriptions reflect cross-platform support — v1.0
- ✓ Umbrella router `/upkeep` delivers same Linux/WSL2 experience as dedicated sub-skills — v1.0

### Active

(No active requirements — planning next milestone)

### Out of Scope

- Windows native (CMD/PowerShell) — not a target; WSL2 is the Windows story
- FreeBSD / other Unix — defer; focus on Linux distros and WSL2
- GUI / desktop notifications — skill is terminal-only by design
- Automated (cron) mode — not in scope for this milestone
- AUR helpers (yay/paru) — deferred to v2
- AppImage audit/cleanup — deferred to v2
- Wayland/X11 session cache cleanup — deferred to v2
- Windows Recycle Bin via WSL2 — deferred to v2
- WSL2 distro export/import size management — deferred to v2

## Context

upkeep skills are markdown files consumed by Claude Code. The "code" is Claude's instruction set, not shell scripts. OS awareness is implemented as:
1. OS detection bash snippets at the top of each skill (`$OS_TYPE`, `$OS_DISTRO`, `$PKG_MGR`)
2. macOS-specific phases wrapped in OS guards (skip gracefully on Linux/WSL2)
3. Linux-equivalent phase sections added after macOS guards
4. SKILL.md `allowed-tools` frontmatter updated with Linux commands

**Shipped v1.0:** 5 skill files, 64 files changed, ~10,950 lines across 6 phases.

**Tech stack:** Pure markdown SKILL.md instruction files. No build step, no runtime. Consumed by Claude Code `allowed-tools` frontmatter.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| OS detection at phase entry, not per-command | Cleaner skill instructions; phases self-skip rather than every command being guarded | ✓ Good — consistent pattern across all 5 skills |
| Shared OS detection snippet per skill (not a shared file) | Skills are standalone — can't `source` a shared file in Claude Code skill context | ✓ Good — each skill is self-contained |
| WSL2 treated as Linux + Windows extras | WSL2 runs Linux; build on Linux support then add Windows-side bonus cleanup | ✓ Good — layered cleanly |
| Linux distro support: Debian/Ubuntu (apt), Fedora/RHEL (dnf), Arch (pacman) | Covers ~90% of Linux desktop users; others get graceful skips | ✓ Good — covers target audience |
| sudo upgrade surfaced as Manual Steps prose only | Skill never runs sudo; consistency with existing safety rule | ✓ Good — safety preserved |
| snap/flatpak gated by `command -v`, not `$OS_TYPE` | Handles rare non-Linux installs (Homebrew Linuxbrew, etc.) | ✓ Good — more robust |
| Umbrella router phases embedded inline (not sub-skill calls) | Claude Code skills are standalone; can't delegate to other skills mid-execution | ✓ Good — no runtime coupling |
| Gap closure phases 5+6 added after initial audit | Initial 4 phases targeted sub-skills only; umbrella needed separate pass | ✓ Good — audit caught the gap; gap closure closed it |

## Constraints

- **Compatibility**: Must not break existing macOS behavior — all changes are additive guards, not replacements
- **No sudo**: Skill never runs sudo; applies to Linux too; upgrade commands shown as Manual Steps prose only
- **Skill format**: Implementation lives in SKILL.md instruction files, not shell scripts
- **Approval gates**: Any removal operations still require user confirmation (existing pattern)

---
*Last updated: 2026-04-19 after v1.0 milestone — Linux & WSL2 Cross-Platform Support shipped*
