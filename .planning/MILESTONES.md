# Milestones

## v1.0 Linux & WSL2 Cross-Platform Support (Shipped: 2026-04-19)

**Phases completed:** 6 phases, 17 plans  
**Timeline:** 2026-04-16 → 2026-04-19 (4 days)  
**Files changed:** 64 files, ~10,950 lines added

**Key accomplishments:**

1. All 5 upkeep skills detect OS/distro at runtime via shared `$OS_TYPE`/`$PKG_MGR` environment detection snippet — macOS-only phases skip gracefully on Linux/WSL2
2. cleandeep, cleanquick, and audit deliver complete Linux cleanup (apt/dnf/pacman cache, journald vacuum, ~/.cache sweep, Snap & Flatpak orphan removal)
3. WSL2 environment detected with banner; Windows-side temp and npm/pip cache cleanup offered via `/mnt/c/` bridge
4. update skill routes to Linux package managers (apt/dnf/pacman/snap/flatpak) with per-tool confirmation gates; Windows pkg managers audited in WSL2 (audit-only, no auto-upgrade)
5. Umbrella router (`/upkeep`) fully ported — 5 integration gaps (MISS-1 through MISS-5) closed, delivering same Linux/WSL2 experience as dedicated sub-skills
6. README, badges, and descriptions updated to reflect macOS 14+ / Linux / WSL2 support across all distro families

**Archive:** `.planning/milestones/v1.0-ROADMAP.md`

---
