# Milestones

## v1.1 Update Skill Overhaul — macOS Parallel Flow (Shipped: 2026-05-07)

**Phases completed:** 5 phases, 5 plans
**Timeline:** 2026-05-07 11:47 → 16:12 (single-day milestone, ~4h25m)
**Files changed:** 30 files, +2,680 / −27 lines (11 commits across 2 PRs)
**PRs:** [#8 — initial v1.1](https://github.com/KyleNesium/upkeep/pull/8), [#9 — gap closure](https://github.com/KyleNesium/upkeep/pull/9)

**Key accomplishments:**

1. `/upkeep:update` on macOS now uses four parallel scout agents (skills, native, language, shadow) instead of ~30s of sequential bash — fan-out is a single tool-use block, structured JSON output per scout.
2. Compatibility synthesizer agent + new `compatibility.json` (9 dependency edges) flag cross-manager risks before approval: brew:node ⇒ npm globals, brew:openssl ⇒ ruby native gems (nokogiri, sassc, etc.), brew:python ⇒ pipx + uv. Severity tiers (`severity_on_major` / `severity_on_minor`) sort the Risks block high → medium → low.
3. Single approval gate replaces per-category Y/N fatigue. Drop-categories follow-up preserves opt-out per ecosystem; macOS update restart prompt remains a separate gate even under "Apply all".
4. Apply orchestrator parallelizes independent ecosystems (npm + pipx + gems + uv + bun, 4-job cap); brew runs alone; mas/macOS last. Per-tool isolation wrapper records ✓/✗ without blocking other tools.
5. System-Ruby auto-detection forces `gem update --user-install` (closes the silent sudo-required failure mode); disk-space pre-flight refuses < 5 GB; codex `~/.codex/skills/*/.git` repos auto-update like Claude skills.
6. Post-flight runs `brew doctor`, re-resolves PATH for upgraded binaries (`$UPGRADED_FORMULAS` / `$UPGRADED_TOOLS` populated via temp-file accumulators, race-safe under POSIX), aggregates deprecation warnings. ETA self-tunes from `~/.claude/data/upkeep-history.json` median over the last 5 runs.

**Audit:** `passed` after gap-closure PR #9 — all 19 requirements wired, 5/5 phases verified, 8/8 cross-phase contracts traced clean. Five runtime claims (R1 wall-time, R8 `--user-install`, N4 partial-failure, G1 ETA self-tune, G3 restart gate, G4 schema-mismatch) deferred to populated-machine PR test plans.

**Archive:** `.planning/milestones/v1.1-ROADMAP.md`, `.planning/milestones/v1.1-REQUIREMENTS.md`, `.planning/milestones/v1.1-MILESTONE-AUDIT.md`

---

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
