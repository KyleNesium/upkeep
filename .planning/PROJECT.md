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
- ✓ Parallel discovery via four scout agents (skills, native, language, shadow) on macOS — v1.1
- ✓ Compatibility synthesizer agent + `compatibility.json` matrix flags cross-manager risks — v1.1
- ✓ Single approval gate replaces per-category Y/N fatigue on macOS — v1.1
- ✓ Apply orchestrator parallelizes independent ecosystems (4-job cap), brew exclusive, mas/macOS last — v1.1
- ✓ macOS system-Ruby auto-detection forces `gem update --user-install` — v1.1
- ✓ PATH shadow detection + brew doctor + deprecation aggregator in post-flight — v1.1
- ✓ Disk-space pre-flight (refuse < 5 GB, warn < 10 GB) — v1.1
- ✓ Codex `~/.codex/skills/*/.git` repos auto-update like Claude skills — v1.1
- ✓ History-tuned ETA self-tunes from `~/.claude/data/upkeep-history.json` median — v1.1
- ✓ Schema-version refusal gate routes mismatched plans to fallback — v1.1

### Active

(No active requirements — planning next milestone)

#### Runtime verification queue (carried into next milestone)

These v1.1 claims are wired in source but require live macOS validation:
- R1 — discovery wall time ≤ 50% of v1.0 sequential
- R8 — `gem update --user-install` actual auto-injection on Ruby 2.x machine
- N4 — partial-failure resilience under synthetic mid-run brew failure
- G1 runtime — ETA self-tuning measurable difference on second run
- G3 runtime — restart gate fires when a real macOS update is pending
- G4 runtime — schema-mismatch payload routes to fallback as designed

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

**Shipped v1.1:** macOS update flow rewritten — 4 parallel scout agents + 1 compatibility synthesizer agent + single-gate apply + post-flight health check. 30 files changed, +2,680 LOC across 5 phases (single-day milestone, 11 commits, 2 PRs). Linux/WSL2 paths preserved unchanged. New sibling data file: `compatibility.json` (9 cross-manager dependency edges).

**Tech stack:** Pure markdown SKILL.md instruction files plus optional sibling JSON data files. No build step, no runtime. Consumed by Claude Code `allowed-tools` frontmatter. v1.1 introduces inline `Agent` invocations from within the skill — first time the project uses sub-agent fan-out.

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
| v1.1 Mac-only first; Linux/WSL2 port deferred | New parallel-agent architecture worth proving on the test machine before porting | ✓ Good — v1.0 sequential paths preserved unchanged; v1.1.x can port |
| Four parallel scouts vs single big bash with `&` | Scouts get domain-specific reasoning; bash background jobs don't compose with Claude Code tool calls | ✓ Good — parallel fan-out lands in single tool-use block |
| Inline `Agent` invocations from a skill | First project use; fits Claude Code's skill model and reduces orchestrator context | ✓ Good — discovery + synthesis agents both work cleanly |
| Static `compatibility.json` matrix vs LLM-proposed edges | LLM hallucination risk on dependency edges is too high; matrix is hand-curated | ✓ Good — 9 seed edges cover the common Mac dev stack |
| Gap closure as new phases 10–11 vs amending phases 7–9 | Audit-traceability — keep verified phases sealed, add new phases for new work | ✓ Good — clean PR diff (PR #9), preserved verification of #7–9 |
| Single-day milestone delivery | All work was tightly coupled (scouts → synthesizer → apply); splitting would have created false phase boundaries | ✓ Good — 4h25m delivery for 5 phases via 2 PRs |

## Constraints

- **Compatibility**: Must not break existing macOS behavior — all changes are additive guards, not replacements
- **No sudo**: Skill never runs sudo; applies to Linux too; upgrade commands shown as Manual Steps prose only
- **Skill format**: Implementation lives in SKILL.md instruction files, not shell scripts
- **Approval gates**: Any removal operations still require user confirmation (existing pattern)

---
*Last updated: 2026-05-07 after v1.1 milestone — Update Skill Overhaul (macOS parallel flow) shipped*
