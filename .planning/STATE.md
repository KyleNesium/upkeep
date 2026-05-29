---
gsd_state_version: 1.0
milestone: v1.5
milestone_name: Single-Shot Orchestrator (macOS Fast Path)
status: in_review
stopped_at: PR #16 draft open 2026-05-28; awaiting codex review + live apply
last_updated: "2026-05-28T19:10:00.000Z"
progress:
  total_phases: 6
  completed_phases: 5
  total_plans: 6
  completed_plans: 5
---

# Project State

## Project Reference

See: `.planning/PROJECT.md`

**Core value:** Every upkeep command gracefully handles macOS, Linux, and WSL2 without errors, with macOS as the bleeding edge.
**Current focus:** v1.5 — make `/upkeep:update` actually fast enough for routine use, not just "8x faster than v1.3" on paper.

## Current Position

Six milestones shipped since v1.0:
- v1.0 (2026-04-19): Linux/WSL2 cross-platform
- v1.1 (2026-05-07): macOS parallel discovery + synthesizer
- v1.2 (2026-05-07, + v1.2.1, v1.2.2): security hardening
- v1.3 (2026-05-11, + v1.3.1): update advisor
- v1.4 (2026-05-18): fast discovery + synthesis scripts (8x speedup)
- v1.5 (in PR #16, 2026-05-28): single-shot orchestrator + brew TTL cache + pattern-table diagnoser

v1.5 PR #16 is **draft**. Five of six v1.5 phases complete; Phase 5 (eager-discovery hook) deferred since acceptance targets hit without it.

## Accumulated Context

### Key Decisions (current)

- **Skill = thin wrapper, not orchestrator.** v1.4 moved discovery/synthesis to bash but SKILL.md still orchestrated the apply phase across 5+ LLM turns. v1.5 collapses everything into `scripts/update.sh`; SKILL.md just renders the gate and report. Measured 12–18x user-perceived speedup.
- **Cache brew metadata aggressively.** `brew update` was the 8–14s long pole on every discovery. The sentinel exists (`~/Library/Caches/Homebrew/api/formula.jws.json` mtime), so TTL-cache it. 1h default is short enough that real users get fresh-enough metadata; `UPKEEP_NO_CACHE=1` for the paranoid.
- **Failure diagnosis is pattern-matched, not LLM.** ~80% of failures match well-known patterns (Ruby version, native build deps, EACCES, pipx ImportError, dyld, arch, solver, brew post-install). Hand-authored case statement is faster (100x+), deterministic, easier to extend. LLM fallback only via "Investigate manually" diagnosis when no pattern matches.
- **Enrichment is opt-in, not gated.** v1.3/v1.4 gated `changelog-reader` + `project-impact` on "brew major bump OR medium+ compat edge." Still added 30–60s for users with majors. v1.5 makes them strictly opt-in (`--advisor`) and moves them to after the gate, in parallel with apply.

### Pending Todos

1. Run codex adversarial review on `scripts/update.sh` and `scripts/diagnose.sh` before merging PR #16. v1.3.1's five fixes came from this pattern.
2. Once user runs `/plugin update upkeep` to pull v1.5 onto the live box, run a real `/upkeep:update packages` to exercise the apply path (dispatcher, post-flight, history write, diagnose.sh against actual gem failures on system Ruby 2.6).
3. After merge: tag v1.5.0, write GitHub release notes from CHANGELOG section, delete `feat/v1.5-single-shot` branch.
4. Plan v1.6 Linux/WSL2 fast-path port.

### Carried-Forward Runtime Claims

From v1.1 STATE.md, six runtime claims (R1, R8, N4, G1, G3, G4 runtime) have been deferred for live macOS box validation. v1.4 live-validation on 2026-05-27 partially covered them via discovery + synthesis. Full coverage requires a real apply run (still pending v1.5 plugin install).

### Blockers/Concerns

- v1.5 cannot be live-apply-tested until user runs `/plugin update upkeep` to install v1.5 over the still-present v1.3.0 plugin cache. (v1.4 was tagged but never landed on this machine for the same reason — `/plugin update` is opt-in.)
- The 5s warm-cache floor in `discover.sh` is dominated by the parallel sections (skills walk + language scout + shadow walk). Further reduction needs either eager-discovery hook (deferred) or aggressive caching of skills git fetch / `gem outdated`.

## Session Continuity

Last session: 2026-05-28
Stopped at: PR #16 draft opened; codex review + live apply pending.
Branch: `feat/v1.5-single-shot`
PR: https://github.com/KyleNesium/upkeep/pull/16
Resume file: `.planning/milestones/v1.5-ROADMAP.md`
