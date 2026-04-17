# Requirements: upkeep Linux & WSL2 Support

**Defined:** 2026-04-17
**Core Value:** Every upkeep command gracefully handles macOS, Linux, and WSL2 without errors

## v1 Requirements

### OS Detection

- [x] **OS-01**: All skills detect current OS (macOS / Linux / WSL2) at runtime using `uname`/`/etc/os-release`
- [x] **OS-02**: macOS-only phases are guarded and skip gracefully on Linux/WSL2 with a clear "skipped (macOS only)" note
- [x] **OS-03**: WSL2 is detected separately from plain Linux (via `uname -r | grep -qi microsoft`)
- [x] **OS-04**: Linux distro family is detected (Debian/Ubuntu → apt, Fedora/RHEL → dnf, Arch → pacman) for package manager routing

### Linux Cleanup

- [x] **LNX-01**: cleandeep adds Linux baseline phase (df, /etc/os-release, kernel version, package manager)
- [x] **LNX-02**: cleandeep adds Linux package cache cleanup (apt clean/autoclean/autoremove, dnf clean, pacman -Sc equivalent)
- [x] **LNX-03**: cleandeep adds Linux user cache cleanup (~/.cache/ — size audit + selective removal with approval)
- [x] **LNX-04**: cleandeep adds Linux systemd journal cleanup (journalctl --disk-usage, vacuum with approval)
- [x] **LNX-05**: cleandeep adds Snap/Flatpak cleanup (snap list, flatpak uninstall --unused) where installed
- [x] **LNX-06**: cleandeep adds orphaned .deb/.rpm files and old kernel cleanup (approval-gated)
- [x] **LNX-07**: cleanquick includes Linux equivalents (package cache, user cache) alongside existing dev cache phases
- [x] **LNX-08**: audit skill reports Linux-specific disk usage and package manager state

### WSL2 Support

- [x] **WSL-01**: All skills detect WSL2 and display environment banner ("Running in WSL2 on Windows")
- [x] **WSL-02**: cleandeep adds WSL2 bonus phase: Windows temp file cleanup via `/mnt/c/Users/$USER/AppData/Local/Temp/` (approval-gated)
- [x] **WSL-03**: cleandeep adds WSL2 bonus phase: Windows %LOCALAPPDATA% npm/pip caches via /mnt/c/ bridge (size audit + optional cleanup)
- [x] **WSL-04**: update skill detects WSL2 and reports Windows package managers (winget, scoop, chocolatey) if accessible — audit only, no auto-upgrade

### Update Skill

- [x] **UPD-01**: update skill supports apt/dnf/pacman upgrade paths (with per-package-manager confirmation gates)
- [x] **UPD-02**: update skill detects and updates snap packages where installed
- [x] **UPD-03**: update skill detects and updates flatpak packages where installed
- [x] **UPD-04**: update skill skips mas and softwareupdate on Linux/WSL2 with a clear skip note

### Tooling & Config

- [x] **CFG-01**: All SKILL.md allowed-tools frontmatter updated with Linux commands (uname, lsb_release, lsblk, apt, dnf, pacman, snap, flatpak, systemctl, journalctl)
- [ ] **CFG-02**: upkeep SKILL.md description updated to reflect cross-platform support
- [ ] **CFG-03**: README updated — prerequisites, badges, and platform section reflect macOS 14+ / Linux / WSL2

## v2 Requirements

### Extended Linux Support

- **LNX-V2-01**: Arch Linux AUR helper cleanup (yay, paru)
- **LNX-V2-02**: AppImage audit and cleanup
- **LNX-V2-03**: Wayland/X11 session cache cleanup

### WSL2 Extended

- **WSL-V2-01**: Windows Recycle Bin audit via WSL2 bridge
- **WSL-V2-02**: WSL2 distro export/import size management

## Out of Scope

| Feature | Reason |
|---------|--------|
| Windows native (CMD/PowerShell) | Not a Claude Code skill platform; WSL2 is the Windows story |
| FreeBSD / other Unix | Low install base; can be added post-milestone |
| GUI notifications | Skill is terminal-only by design |
| Automated cron mode | Not in scope for this milestone |
| Root/sudo operations | Existing safety rule — never sudo; applies to Linux too |
| macOS behavior changes | All changes must be additive; zero regression for macOS users |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| OS-01 | Phase 1: OS Detection & Config | Complete |
| OS-02 | Phase 1: OS Detection & Config | Complete |
| OS-03 | Phase 1: OS Detection & Config | Complete |
| OS-04 | Phase 1: OS Detection & Config | Complete |
| CFG-01 | Phase 1: OS Detection & Config | Complete |
| LNX-01 | Phase 2: Linux Cleanup | Complete |
| LNX-02 | Phase 2: Linux Cleanup | Complete |
| LNX-03 | Phase 2: Linux Cleanup | Complete |
| LNX-04 | Phase 2: Linux Cleanup | Complete |
| LNX-05 | Phase 2: Linux Cleanup | Complete |
| LNX-06 | Phase 2: Linux Cleanup | Complete |
| LNX-07 | Phase 2: Linux Cleanup | Complete |
| LNX-08 | Phase 2: Linux Cleanup | Complete |
| WSL-01 | Phase 3: WSL2 Support | Complete |
| WSL-02 | Phase 3: WSL2 Support | Complete |
| WSL-03 | Phase 3: WSL2 Support | Complete |
| WSL-04 | Phase 3: WSL2 Support | Complete |
| UPD-01 | Phase 4: Update Skill & Polish | Complete |
| UPD-02 | Phase 4: Update Skill & Polish | Complete |
| UPD-03 | Phase 4: Update Skill & Polish | Complete |
| UPD-04 | Phase 4: Update Skill & Polish | Complete |
| CFG-02 | Phase 4: Update Skill & Polish | Pending |
| CFG-03 | Phase 4: Update Skill & Polish | Pending |

**Coverage:**
- v1 requirements: 23 total
- Mapped to phases: 23
- Unmapped: 0 ✓

---
*Requirements defined: 2026-04-17*
*Last updated: 2026-04-17 after roadmap creation*
