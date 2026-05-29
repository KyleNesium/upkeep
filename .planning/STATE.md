---
gsd_state_version: 1.0
milestone: v1.6
milestone_name: Linux/WSL2 Fast-Path Port
status: in_review
stopped_at: feat/v1.6-linux-fastpath draft PR open 2026-05-29; 67/67 tests green; live Linux validation pending
last_updated: "2026-05-29T00:00:00.000Z"
progress:
  total_phases: 6
  completed_phases: 6
  total_plans: 6
  completed_plans: 6
---

# Project State

## Project Reference

See: `.planning/PROJECT.md`

**Core value:** Every upkeep command gracefully handles macOS, Linux, and WSL2 without errors. As of v1.6 the `update` fast path is unified across all three.
**Current focus:** v1.6 — port the v1.5 single-shot orchestrator to Linux + WSL2 so all platforms share one fast path and one UX.

## Current Position

Seven milestones since v1.0:
- v1.0 (2026-04-19): Linux/WSL2 cross-platform
- v1.1 (2026-05-07): macOS parallel discovery + synthesizer
- v1.2 (2026-05-07, + v1.2.1, v1.2.2): security hardening
- v1.3 (2026-05-11, + v1.3.1): update advisor
- v1.4 (2026-05-18): fast discovery + synthesis scripts (8x speedup)
- v1.5 (2026-05-29): single-shot orchestrator + brew TTL cache + pattern-table diagnoser (shipped, tagged)
- v1.6 (in PR, 2026-05-29): Linux/WSL2 fast-path port — one OS-aware orchestrator for all platforms

v1.6 is in a **draft PR** on `feat/v1.6-linux-fastpath`. All six phases complete (discover/synthesize/update/diagnose/SKILL/docs); 67/67 tests pass under bash 5 and bash 3.2.

## Accumulated Context

### Key Decisions (current)

- **Skill = thin wrapper, not orchestrator.** v1.4 moved discovery/synthesis to bash but SKILL.md still orchestrated the apply phase across 5+ LLM turns. v1.5 collapses everything into `scripts/update.sh`; SKILL.md just renders the gate and report. Measured 12–18x user-perceived speedup.
- **Cache brew metadata aggressively.** `brew update` was the 8–14s long pole on every discovery. The sentinel exists (`~/Library/Caches/Homebrew/api/formula.jws.json` mtime), so TTL-cache it. 1h default is short enough that real users get fresh-enough metadata; `UPKEEP_NO_CACHE=1` for the paranoid.
- **Failure diagnosis is pattern-matched, not LLM.** ~80% of failures match well-known patterns (Ruby version, native build deps, EACCES, pipx ImportError, dyld, arch, solver, brew post-install). Hand-authored case statement is faster (100x+), deterministic, easier to extend. LLM fallback only via "Investigate manually" diagnosis when no pattern matches.
- **Enrichment is opt-in, not gated.** v1.3/v1.4 gated `changelog-reader` + `project-impact` on "brew major bump OR medium+ compat edge." Still added 30–60s for users with majors. v1.5 makes them strictly opt-in (`--advisor`) and moves them to after the gate, in parallel with apply.

### Key Decisions (v1.6)

- **One OS-aware orchestrator, not per-platform scripts.** `discover.sh`/`synthesize.sh`/`update.sh` branch internally on `os.type`. The shared `discover_skills`/`discover_language` are reused verbatim; only the native section differs. Exploited the `// []` jq idiom so macOS-only and Linux-only native keys are naturally inert on the other OS — minimizing macOS regression risk.
- **The sudo boundary.** apt/dnf/pacman require root; upkeep never runs sudo. They are surfaced as `system-sudo` manual_steps and are deliberately excluded from the apply allowlist — the allowlist `_die` is the hard guarantee. snap/flatpak (user-scoped) ARE auto-applied.
- **Test seam over live faking.** `UPKEEP_OS_OVERRIDE`/`UPKEEP_PKG_MGR_OVERRIDE` short-circuit `uname` so Linux paths run on the macOS dev box; PATH-stubbed fake managers feed canned output. 23 new tests (44→67).

### Pending Todos

1. Live-validate the Linux path on a real Debian/Fedora/Arch box (or WSL2) — current coverage is contract-tested only. Confirm real apt-get/dnf/pacman/snap/flatpak output parses as expected.
2. Consider a codex adversarial review of the v1.6 `discover_native_linux` + synthesize Linux branch before merge (the v1.3.1/v1.5 pattern that found real bugs).
3. After merge: tag v1.6.0, write GitHub release notes from CHANGELOG, delete `feat/v1.6-linux-fastpath` branch.
4. Possible v1.7: Linux PATH-shadow detection (deferred from v1.6), Linux-specific compatibility.json edges, eager-discovery hook (deferred from v1.5).

### Carried-Forward Runtime Claims

From v1.1 STATE.md, six runtime claims (R1, R8, N4, G1, G3, G4 runtime) have been deferred for live macOS box validation. v1.4 live-validation on 2026-05-27 partially covered them via discovery + synthesis. Full coverage requires a real apply run (still pending v1.5 plugin install).

### Blockers/Concerns

- v1.6 Linux/WSL2 paths are **contract-tested, not live-validated** — the dev box is macOS, so real apt/dnf/pacman/snap/flatpak behaviour is simulated via PATH stubs + the OS-override seam. Live validation on a real Linux box is the top follow-up.
- macOS regression risk was the main concern; mitigated by keeping macOS code paths byte-for-byte and relying on the existing 44 tests (all still green) plus 2 explicit macOS-regression assertions in Section 10.

## Session Continuity

Last session: 2026-05-29
Stopped at: v1.6 implemented; 67/67 tests green under bash 5 + bash 3.2; draft PR pending push.
Branch: `feat/v1.6-linux-fastpath`
Plan file: `~/.claude/plans/radiant-nibbling-sifakis.md`
