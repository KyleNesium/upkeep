# Roadmap: upkeep Linux & WSL2 Support

## Overview

upkeep is a macOS-only skill set today. This milestone adds OS awareness so every skill gracefully handles macOS, Linux (Debian/Ubuntu, Fedora/RHEL, Arch), and WSL2 — routing to the right cleanup phases and package managers based on detected environment. The work proceeds in four phases: establish detection foundations first, then add Linux cleanup, then WSL2 extras, then Linux support in the update skill and final documentation polish.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: OS Detection & Config** - Add OS/distro detection to all skills and update allowed-tools frontmatter (completed 2026-04-17)
- [x] **Phase 2: Linux Cleanup** - Add Linux-specific phases to cleandeep, cleanquick, and audit skills (completed 2026-04-17)
- [x] **Phase 3: WSL2 Support** - Add WSL2 detection, banner, and Windows-side bonus cleanup phases (completed 2026-04-17)
- [x] **Phase 4: Update Skill & Polish** - Add Linux/WSL2 package upgrade paths; update skill descriptions and README (completed 2026-04-17)

## Phase Details

### Phase 1: OS Detection & Config
**Goal**: Every skill knows what environment it is running in and has permission to use Linux commands
**Depends on**: Nothing (first phase)
**Requirements**: OS-01, OS-02, OS-03, OS-04, CFG-01
**Success Criteria** (what must be TRUE):
  1. Running any upkeep skill on Linux or WSL2 prints the detected OS/distro at the start — it does not error on uname or /etc/os-release
  2. macOS-only phases (mdfind, launchctl, defaults, mas) display a "skipped (macOS only)" note on Linux/WSL2 rather than erroring
  3. WSL2 is identified separately from plain Linux — the skill knows it is inside a Windows host
  4. The distro family (Debian/Ubuntu, Fedora/RHEL, Arch) is resolved so the correct package manager is used downstream
  5. All SKILL.md files list Linux commands (uname, lsb_release, apt, dnf, pacman, systemctl, journalctl, etc.) in their allowed-tools frontmatter
**Plans**: 5 plans
Plans:
- [ ] 01-01-PLAN.md — upkeep router: OS detection + macOS-only phase guards + Linux allowed-tools
- [ ] 01-02-PLAN.md — cleandeep: OS detection + guards for Phases 2/4/5/6/11/14 + Linux allowed-tools
- [ ] 01-03-PLAN.md — cleanquick: OS detection + guards for Phases 2/11 + Linux allowed-tools
- [ ] 01-04-PLAN.md — audit: OS detection + guards for Phases 2/4/5/6/11/14 + Linux allowed-tools
- [ ] 01-05-PLAN.md — update: OS detection + mas/softwareupdate gating in Steps 2/3/5/6 + Linux allowed-tools

### Phase 2: Linux Cleanup
**Goal**: cleandeep, cleanquick, and audit deliver a complete Linux cleanup and reporting experience
**Depends on**: Phase 1
**Requirements**: LNX-01, LNX-02, LNX-03, LNX-04, LNX-05, LNX-06, LNX-07, LNX-08
**Success Criteria** (what must be TRUE):
  1. cleandeep on Linux runs a baseline info phase (df, os-release, kernel version, package manager name) before any cleanup
  2. cleandeep on Linux offers package cache cleanup (apt clean / dnf clean / pacman -Sc equivalent) with a confirmation gate before acting
  3. cleandeep on Linux audits ~/.cache/ size and removes selected entries only after user approval
  4. cleandeep on Linux offers journald vacuum and Snap/Flatpak orphan removal where those tools are installed
  5. cleanquick on Linux runs the package cache and user cache phases alongside existing dev-cache phases
  6. audit on Linux reports disk usage and package manager state without making any changes
**Plans**: 5 plans
Plans:
- [ ] 02-01-PLAN.md — cleandeep: Linux baseline + package cache + orphan cleanup (LNX-01, LNX-02, LNX-06)
- [ ] 02-02-PLAN.md — cleandeep: Linux user cache + systemd journal vacuum (LNX-03, LNX-04)
- [ ] 02-03-PLAN.md — cleandeep: Snap + Flatpak cleanup phase (LNX-05)
- [ ] 02-04-PLAN.md — cleanquick: Linux lightweight package cache + age-based ~/.cache sweep (LNX-07)
- [ ] 02-05-PLAN.md — audit: Linux read-only reporting across baseline/packages/cache/journal/snap+flatpak (LNX-08)

### Phase 3: WSL2 Support
**Goal**: All skills detect WSL2 and cleandeep adds Windows-side bonus cleanup phases
**Depends on**: Phase 2
**Requirements**: WSL-01, WSL-02, WSL-03, WSL-04
**Success Criteria** (what must be TRUE):
  1. Any upkeep skill running inside WSL2 displays an environment banner ("Running in WSL2 on Windows") before the first phase
  2. cleandeep in WSL2 offers to clean Windows temp files at /mnt/c/Users/$USER/AppData/Local/Temp/ — gated behind user approval
  3. cleandeep in WSL2 reports the size of Windows npm/pip caches via the /mnt/c/ bridge and offers optional cleanup
  4. update in WSL2 detects accessible Windows package managers (winget, scoop, chocolatey) and reports their status — no auto-upgrade, audit only
**Plans**: 3 plans
Plans:
- [ ] 03-01-PLAN.md — WSL2 banner in cleanquick / audit / upkeep router (WSL-01)
- [ ] 03-02-PLAN.md — cleandeep: WSL2 banner + Phase 17 Windows Temp + Phase 18 Windows npm/pip cache audit (WSL-01, WSL-02, WSL-03)
- [ ] 03-03-PLAN.md — update: WSL2 banner + Windows package manager detection (winget/scoop/choco, audit only) (WSL-01, WSL-04)

### Phase 4: Update Skill & Polish
**Goal**: update skill supports Linux package managers and all documentation reflects cross-platform reality
**Depends on**: Phase 3
**Requirements**: UPD-01, UPD-02, UPD-03, UPD-04, CFG-02, CFG-03
**Success Criteria** (what must be TRUE):
  1. update on Linux upgrades system packages via apt, dnf, or pacman — each manager has its own confirmation gate before running
  2. update on Linux detects and upgrades snap packages where snap is installed
  3. update on Linux detects and upgrades flatpak packages where flatpak is installed
  4. update on Linux/WSL2 skips mas and softwareupdate with a visible "skipped (macOS only)" note
  5. The upkeep SKILL.md description states cross-platform support and the README shows macOS 14+ / Linux / WSL2 prerequisites and badges
**Plans**: 2 plans
Plans:
- [ ] 04-01-PLAN.md — update/SKILL.md: Linux upgrade paths (apt/dnf/pacman) + snap + flatpak + per-tool mas/softwareupdate skip visibility (UPD-01, UPD-02, UPD-03, UPD-04)
- [ ] 04-02-PLAN.md — Docs polish: upkeep router SKILL.md description + README badges, Prerequisites, and Platform Support section (CFG-02, CFG-03)

### Phase 5: Umbrella Router — Linux Cleanup Phase Parity
**Goal**: upkeep/skills/upkeep/SKILL.md delivers the same Linux/WSL2 cleanup experience as the dedicated sub-skills for all cleanup phases
**Depends on**: Phase 4
**Requirements**: OS-01, LNX-01, LNX-02, LNX-04, LNX-05, LNX-06, WSL-02, WSL-03
**Gap Closure**: Closes MISS-1, MISS-2, MISS-3, MISS-4 from v1.0 audit
**Success Criteria** (what must be TRUE):
  1. Phase 1 Baseline outputs OS-branched info: macOS gets `sw_vers`; Linux/WSL2 gets `/etc/os-release`, `uname -r`, `$PKG_MGR`
  2. Phase 2 on Linux/WSL2 runs the `$PKG_MGR` package cache sweep (apt autoclean / dnf clean / pacman -Sc), approval-gated — not "skipped (macOS only)"
  3. Phase 9 on Linux/WSL2 runs `journalctl --disk-usage` + vacuum approval gate; macOS path is guarded
  4. Phase 16 (Snap & Flatpak), Phase 17 (WSL2 Windows Temp), Phase 18 (WSL2 Windows npm/pip) are present in the umbrella and match cleandeep sub-skill content
**Plans**: 1 plan

### Phase 6: Umbrella Router — Update Mode Linux Parity
**Goal**: upkeep/skills/upkeep/SKILL.md Update Mode Step 5 routes to Linux package managers, snap, flatpak, and WSL2 Windows pkg detection
**Depends on**: Phase 5
**Requirements**: UPD-01, UPD-02, UPD-03, WSL-04
**Gap Closure**: Closes MISS-5 from v1.0 audit
**Success Criteria** (what must be TRUE):
  1. Update Mode Step 5 on Linux/WSL2 routes to `$PKG_MGR` case dispatch (apt/dnf/pacman upgrades) with approval gate — not table-only output
  2. Update Mode Step 5 detects snap via `command -v snap` and runs `snap refresh --list` → approval → `snap refresh`
  3. Update Mode Step 5 detects flatpak via `command -v flatpak` and runs list preview → approval → `flatpak update -y`
  4. Update Mode Step 2 on WSL2 detects Windows package managers (winget/scoop/choco) via `/mnt/c/` guard — audit only, no upgrade
**Plans**: 1 plan

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. OS Detection & Config | 5/5 | Complete    | 2026-04-17 |
| 2. Linux Cleanup | 5/5 | Complete   | 2026-04-17 |
| 3. WSL2 Support | 3/3 | Complete   | 2026-04-17 |
| 4. Update Skill & Polish | 2/2 | Complete   | 2026-04-17 |
| 5. Umbrella Router — Linux Cleanup Phase Parity | 0/1 | Not Started | — |
| 6. Umbrella Router — Update Mode Linux Parity | 0/1 | Not Started | — |
