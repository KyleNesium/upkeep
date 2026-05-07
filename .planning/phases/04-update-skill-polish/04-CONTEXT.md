# Phase 4: Update Skill & Polish - Context

**Gathered:** 2026-04-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Complete Linux support in the update skill and update all documentation to reflect cross-platform reality. Phase 1 added macOS guards + Linux allowed-tools; Phase 3 added WSL2 Windows package manager detection. Phase 4 adds the Linux upgrade paths (apt/dnf/pacman, snap, flatpak), ensures mas/softwareupdate show visible skip notes on Linux/WSL2, and updates the upkeep router description and README to reflect macOS 14+ / Linux / WSL2 support.

</domain>

<decisions>
## Implementation Decisions

### All implementation choices are at Claude's discretion — pure infrastructure phase

Phase 4 follows established patterns:
- UPD-01: Linux upgrade paths route via `$PKG_MGR` (apt/dnf/pacman), each with its own confirmation gate before running upgrades — mirror the macOS Homebrew upgrade pattern
- UPD-02: Snap updates: `snap refresh --list` (dry-run preview) → approval gate → `snap refresh` on yes — only when `command -v snap` succeeds
- UPD-03: Flatpak updates: `flatpak update --assumeyes --noninteractive` → only when `command -v flatpak` succeeds — preceded by `flatpak update --dry-run` or list preview
- UPD-04: mas/softwareupdate already gated from Phase 1; ensure each produces a visible "Skipped (macOS only)" echo line when `$OS_TYPE != "macos"` — may already be present, verify first
- CFG-02: upkeep/skills/upkeep/SKILL.md — update the `description:` frontmatter and/or the intro paragraph to mention Linux and WSL2
- CFG-03: README.md at project root — add/update prerequisites section (macOS 14+ / Linux / WSL2), update any macOS-only badges or language

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `$OS_TYPE`, `$PKG_MGR` — already set by Environment Detection in update/SKILL.md (Phase 1)
- Phase 3 Windows package manager detection block in Step 2 — reference for how WSL2 blocks are structured
- Phase 2 Linux cleanup approval gate pattern — mirror for upgrade confirmation gates

### Established Patterns
- Never sudo — upgrade commands must be user-space or show sudo variant in Manual Steps only
- `command -v <tool>` guard before optional tools (snap, flatpak)
- Per-package-manager confirmation: show what will be upgraded, ask yes/no, run only on yes
- Display sizes/counts before asking

### Integration Points
- update/SKILL.md: add Linux upgrade sections to Step 5 (Apply Package Updates) — after the macOS brew block, before the existing mas/softwareupdate block
- upkeep/skills/upkeep/SKILL.md: description frontmatter + intro paragraph
- README.md: prerequisites + any platform language

</code_context>

<specifics>
## Specific Ideas

- apt upgrade: `apt-get upgrade --dry-run 2>/dev/null | grep "^Inst"` → show count → approval gate → `apt-get upgrade -y`
- dnf upgrade: `dnf upgrade --assumeno 2>/dev/null | grep "^Upgrade"` → show count → approval gate → `dnf upgrade -y`
- pacman upgrade: `pacman -Syu --print-format "%n %v" 2>/dev/null` → show list → approval gate → `pacman -Syu --noconfirm`
- snap refresh: `snap refresh --list 2>/dev/null` → show pending updates → approval gate → `snap refresh`
- flatpak update: `flatpak update --no-deploy 2>/dev/null | head -20` or just `flatpak list --app` → approval gate → `flatpak update -y`
- README: add "## Platform Support" section with table: macOS 14+, Ubuntu/Debian, Fedora/RHEL, Arch Linux, WSL2 (Ubuntu/Debian)

</specifics>

<deferred>
## Deferred Ideas

- AUR helper updates (yay/paru) → v2 (LNX-V2-01)
- winget/scoop/choco upgrades from update skill → deferred (Phase 3 confirmed audit-only)
- AppImage update management → out of scope

</deferred>

---
*Phase: 04-update-skill-polish*
*Context gathered: 2026-04-17 via autonomous smart discuss (infrastructure phase)*
