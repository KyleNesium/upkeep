# Phase 2: Linux Cleanup - Context

**Gathered:** 2026-04-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Add Linux-specific cleanup phases to cleandeep, cleanquick, and audit. Phase 1 installed OS detection + macOS guards — Phase 2 adds the Linux-side content that runs when `$OS_TYPE` is `linux` or `wsl2`. Delivers a complete Linux cleanup experience: package cache, user cache, systemd journal, Snap/Flatpak, and orphaned kernel/package cleanup.

</domain>

<decisions>
## Implementation Decisions

### All implementation choices are at Claude's discretion — pure infrastructure phase

Phase 2 adds Linux cleanup bodies to existing macOS-guarded phases. All implementation choices follow the established patterns from Phase 1:
- Use `$OS_TYPE` and `$PKG_MGR` variables set by the Environment Detection snippet
- Mirror macOS phase structure: show sizes, ask before removing, never sudo
- Add `elif [ "$OS_TYPE" != "macos" ]` blocks alongside existing macOS-only guards
- Follow existing approval-gate pattern from macOS phases
- cleanquick gets lightweight equivalents (quick sweep only)
- audit gets read-only equivalents (no removals)

Requirements to cover: LNX-01, LNX-02, LNX-03, LNX-04, LNX-05, LNX-06, LNX-07, LNX-08

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `$OS_TYPE`, `$OS_DISTRO`, `$PKG_MGR` — set by Environment Detection snippet (Phase 1)
- Existing macOS phase guard pattern: `[ "$OS_TYPE" != "macos" ] && echo "Phase N: skipped (macOS only)..." && halt`
- Existing approval-gate pattern from macOS phases — mirror for Linux removals

### Established Patterns
- Phase structure: baseline size → dry-run → ask user → execute with approval
- Never sudo — applies to Linux too
- `command -v <tool>` guard before using any optional tool
- Display sizes before asking to remove

### Integration Points
- cleandeep/SKILL.md — add Linux bodies to phases 2, 4, 5, 6, 11, 14 (after existing macOS guard)
- cleanquick/SKILL.md — add Linux bodies to phases 2, 11
- audit/SKILL.md — add Linux read-only reporting to same phases

</code_context>

<specifics>
## Specific Ideas

Linux cleanup phases to implement:
- Package cache: `apt clean` / `dnf clean all` / `pacman -Sc` (distro-based via $PKG_MGR)
- User cache: `du -sh ~/.cache/` → selective removal with approval
- Systemd journal: `journalctl --disk-usage` → `journalctl --vacuum-size=500M` with approval
- Snap: `snap list --all` → remove disabled revisions with approval (if snap installed)
- Flatpak: `flatpak uninstall --unused` (if flatpak installed)
- Orphaned packages/old kernels: `apt autoremove --dry-run` / `dnf autoremove --dry-run` with approval

</specifics>

<deferred>
## Deferred Ideas

- WSL2-specific Windows temp cleanup → Phase 3
- Linux package manager upgrades (apt upgrade, dnf upgrade) → Phase 4 (update skill)
- AUR helper cleanup (yay/paru) → v2

</deferred>

---
*Phase: 02-linux-cleanup*
*Context gathered: 2026-04-17 via autonomous smart discuss (infrastructure phase)*
