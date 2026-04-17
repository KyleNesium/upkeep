# upkeep — Linux & WSL2 Cross-Platform Support

## What This Is

upkeep is a Claude Code skill that does discovery-based system cleanup and package updates. It currently runs on macOS 14+ only. This milestone adds full OS awareness so the same skill works on macOS, Linux (Ubuntu, Debian, Fedora, Arch, and derivatives), and WSL2 — routing to the right cleanup phases and package managers based on detected environment.

## Core Value

Every upkeep command gracefully handles all three environments (macOS, Linux, WSL2) without errors, skipping unavailable phases rather than failing.

## Requirements

### Validated

- ✓ macOS deep clean (15-phase audit + cleanup) — v1.0.x
- ✓ Quick cleanup (caches + brew) — v1.0.x
- ✓ Audit mode (report only, no changes) — v1.0.x
- ✓ Update skill (git-based skills + package managers) — v1.0.x
- ✓ Discovery-based orphan detection — v1.0.x

### Active

- ✓ OS detection utility shared across all skills (macOS / Linux / WSL2) — Validated in Phase 1: OS Detection & Config
- ✓ Linux-specific cleanup phases (apt cache, snap, flatpak, systemd, journald, ~/.cache) — Validated in Phase 2: Linux Cleanup
- ✓ All SKILL.md allowed-tools updated with Linux commands — Validated in Phase 1: OS Detection & Config
- ✓ WSL2 detection and Windows-side cleanup via /mnt/c/ — Validated in Phase 3: WSL2 Support
- [ ] Linux package manager support in update skill (apt, dnf, pacman, snap, flatpak)
- [ ] README and badges reflect cross-platform support

### Out of Scope

- Windows native (CMD/PowerShell) — not a target; WSL2 is the Windows story
- FreeBSD / other Unix — defer; focus on Linux distros and WSL2
- GUI / desktop notifications — skill is terminal-only by design
- Automated (cron) mode — not in scope for this milestone

## Context

upkeep skills are markdown files consumed by Claude Code. The "code" is Claude's instruction set, not shell scripts. OS awareness means:
1. Adding OS detection bash snippets at the top of each skill
2. Wrapping macOS-specific phases in OS guards
3. Adding Linux-equivalent phase sections
4. Updating SKILL.md `allowed-tools` frontmatter for Linux commands

macOS-specific tools that need Linux equivalents:
- `sw_vers` → `/etc/os-release`, `lsb_release`, `uname`
- `diskutil` → `df`, `lsblk`
- `mdfind`/`mdutil` → not applicable on Linux (skip gracefully)
- `defaults`/`PlistBuddy` → not applicable on Linux (skip gracefully)
- `launchctl`/LaunchAgents → `systemctl` / `~/.config/systemd/user/`
- `mas`/`softwareupdate` → `apt`/`dnf`/`pacman`/`snap`/`flatpak`
- `xcode-select`/`xcrun` → skip gracefully on Linux
- `brew` → `apt`, `dnf`, `pacman` (Homebrew also available on Linux but not primary)

WSL2 detection: `uname -r | grep -qi microsoft`
WSL2 extras: Windows temp files via `/mnt/c/Users/$WIN_USER/AppData/Local/Temp/`

## Constraints

- **Compatibility**: Must not break existing macOS behavior — all changes are additive guards, not replacements
- **No sudo**: Existing safety rule — skill never runs sudo; applies to Linux too
- **Skill format**: Implementation lives in SKILL.md instruction files, not shell scripts
- **Approval gates**: Any removals still require user confirmation (existing pattern)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| OS detection at phase entry, not per-command | Cleaner skill instructions; phases self-skip rather than every command being guarded | — Pending |
| Shared OS detection snippet in each skill (not a separate file) | Skills are standalone — can't `source` a shared file in Claude Code skill context | — Pending |
| WSL2 treated as Linux + Windows extras | WSL2 runs Linux; build on Linux support then add Windows-side bonus cleanup | — Pending |
| Linux distro support: Debian/Ubuntu (apt), Fedora/RHEL (dnf), Arch (pacman) | Covers ~90% of Linux desktop users; others get graceful skips | — Pending |

---
*Last updated: 2026-04-17 after Phase 3 (WSL2 Support) — OS detection, Linux cleanup, and WSL2 support complete*
