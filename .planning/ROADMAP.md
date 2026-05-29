# Roadmap: upkeep

## Milestones

- ✅ **v1.0 Linux & WSL2 Cross-Platform Support** — Phases 1–6 (shipped 2026-04-19)
- ✅ **v1.1 Update Skill Overhaul (macOS-only)** — Phases 7–11 (shipped 2026-05-07)
- ✅ **v1.2 Security Hardening** — hardcoded dispatcher, discovery sanitization, exact-match URL validation, trust-on-first-use (shipped 2026-05-07; v1.2.1 self-update fix 2026-05-08; v1.2.2 review findings 2026-05-08)
- ✅ **v1.3 Update Advisor** — changelog-reader + project-impact enrichment agents, failure-diagnoser, per-tool logging (shipped 2026-05-11; v1.3.1 codex-review findings shipped 2026-05-13)
- ✅ **v1.4 Fast Discovery + Synthesis** — replaced four scout agents + synthesizer with `scripts/discover.sh` + `scripts/synthesize.sh`, 8x speedup of discovery+plan (shipped 2026-05-18)
- ✅ **v1.5 Single-Shot Orchestrator** — collapsed macOS flow into one shell script, brew-update TTL cache, pattern-table failure diagnoser, opt-in enrichment. ~12–18x faster user-perceived pre-gate. (shipped 2026-05-29; PR #16/#17 merged, tagged v1.5.0)
- 🟡 **v1.6 Linux/WSL2 Fast-Path Port** — brought the v1.5 single-shot architecture to apt/dnf/pacman + snap/flatpak + WSL2. One OS-aware orchestrator for all platforms; sudo managers surfaced as manual steps; legacy sequential flow retired. 44→67 tests. (in PR, 2026-05-29; contract-tested, live Linux validation pending)

## Phases

<details>
<summary>✅ v1.0 Linux & WSL2 Cross-Platform Support (Phases 1–6) — SHIPPED 2026-04-19</summary>

- [x] Phase 1: OS Detection & Config (5/5 plans) — 2026-04-17
- [x] Phase 2: Linux Cleanup (5/5 plans) — 2026-04-17
- [x] Phase 3: WSL2 Support (3/3 plans) — 2026-04-17
- [x] Phase 4: Update Skill & Polish (2/2 plans) — 2026-04-17
- [x] Phase 5: Umbrella Router — Linux Cleanup Phase Parity (1/1) — 2026-04-18
- [x] Phase 6: Umbrella Router — Update Mode Linux Parity (1/1) — 2026-04-19

Full details: `.planning/milestones/v1.0-ROADMAP.md`

</details>

<details>
<summary>✅ v1.1 Update Skill Overhaul (Phases 7–11) — SHIPPED 2026-05-07</summary>

- [x] Phase 7: Parallel Discovery Agents (1/1) — 2026-05-07
- [x] Phase 8: Compatibility Synthesizer (1/1) — 2026-05-07
- [x] Phase 9: Single-Gate Apply + Post-Flight (1/1) — 2026-05-07
- [x] Phase 10: Synthesizer Prompt & Context Fixes (R5/R10/G5) — 2026-05-07
- [x] Phase 11: Apply Orchestrator Wiring (R7/G4) — 2026-05-07

Full details: `.planning/milestones/v1.1-ROADMAP.md`

</details>

<details>
<summary>✅ v1.2 Security Hardening — SHIPPED 2026-05-07 (plus 1.2.1 / 1.2.2 patch series)</summary>

Addressed prompt-injection risk discovered in the v1.1 LLM-authored dispatcher.

- Hardcoded dispatcher allowlist (`skills brew npm pipx gems uv bun mas macos`); `tool_specs[].command` and `.preconditions` are ignored
- Discovery JSON sanitization: 256-char string cap + free-text denylist before any LLM agent receives discovery
- Exact-match remote URL validation for skill repos (substring match was bypassable)
- Trust-on-first-use for new skill remotes via `~/.claude/data/upkeep-skill-trust.json`
- Plan/Apply turn separation enforced as hard rule

v1.2.1 (2026-05-08): self-update check correctly handles plugin-cache installs.
v1.2.2 (2026-05-08): closed first-pass review findings (skills regression + drift + perf).

</details>

<details>
<summary>✅ v1.3 Update Advisor — SHIPPED 2026-05-11 (plus 1.3.1 patch series)</summary>

Added human-context layer to the approval gate.

- `changelog-reader` agent: WebFetch to allowlisted hosts (github.com, gitlab.com, etc.), extracts severity/breaking/CVE/action_required per upgrade
- `project-impact` agent: scans `~/workspace`, `~/Github`, `~/Projects`, `~/src`, `~/code`, `~/dev` for manifests pinned to about-to-change versions
- `failure-diagnoser` agent: post-apply, fires per-tool with per-tool log excerpt
- Per-tool logging (replaces global log slice)
- Enrichment gating: only fires when there's a brew major bump or compat-matrix medium+ edge

v1.3.1 (2026-05-13): five critical bugs found by codex adversarial review in the v1.3 macOS parallel flow's apply orchestration and Step 4.5m diagnoser paths; all fixed.

</details>

<details>
<summary>✅ v1.4 Fast Discovery + Synthesis — SHIPPED 2026-05-18</summary>

- `scripts/discover.sh` replaces the four scout agents (skills, native, language, shadow). Inline bash + jq, four parallel sections. `brew update` runs in discovery so the outdated list is accurate before approval.
- `scripts/synthesize.sh` replaces the synthesizer agent. Pure deterministic logic (semver classification, compat-matrix edge materialisation, ETA bake-ins, `gems.user_install`) in jq/bash, ~300ms.
- Enrichment gates aggressively — only fires for brew majors or medium+ compat edges.
- Discovery + plan wall time: ~120s → ~15s (8x).

Full details: `.planning/milestones/v1.4-ROADMAP.md` (if archived) / CHANGELOG entry.

</details>

<details>
<summary>🟡 v1.5 Single-Shot Orchestrator — IN PROGRESS (PR #16 draft, 2026-05-28)</summary>

User feedback: v1.4's 8x discovery speedup wasn't enough — user-perceived pre-gate latency was still ~60–90s due to multi-turn SKILL.md overhead + enrichment agents in the critical path.

- [x] Phase 1: `scripts/update.sh` single-shot orchestrator (plan + apply commands). SKILL.md: 1845 → 767 lines.
- [x] Phase 2: brew-update TTL cache in `discover.sh` (sentinel: `formula.jws.json` mtime, default 3600s, `UPKEEP_NO_CACHE=1` bypass).
- [x] Phase 3: enrichment moved out of pre-gate path; opt-in via `--advisor`.
- [x] Phase 4: `scripts/diagnose.sh` pattern-table replaces v1.3 `failure-diagnoser` agent (8 patterns, ~100ms vs ~10–20s LLM).
- [ ] Phase 5: SessionStart eager-discovery hook — deferred (targets hit without it).
- [x] Phase 6: refresh stale planning docs through v1.5.

Acceptance targets:
- Warm-cache plan to gate: <5s ✅ (measured ~5.1s avg)
- Audit-mode end-to-end: <5s (target was <3s; measured ~5.4s — limited by discover.sh parallel sections floor)
- User-perceived pre-gate: 12–18x improvement over v1.4 measured

Full details: `.planning/milestones/v1.5-ROADMAP.md`.

Remaining before merge:
- Codex adversarial review of `update.sh` + `diagnose.sh` (the v1.3.1 pattern)
- Live `/upkeep:update packages` apply after `/plugin update upkeep`

</details>

<details>
<summary>⏳ v1.6 Linux/WSL2 Fast-Path Port — PLANNING</summary>

The v1.5 single-shot architecture is macOS-only. Linux + WSL2 still run the v1.0 sequential flow (SKILL.md Steps 1–6). Port plan:

- Extract apt/dnf/pacman + snap/flatpak audit + apply commands into `update.sh`'s dispatcher.
- Replace per-category "Apply X?" gates with a single approval gate matching macOS UX.
- Reuse `diagnose.sh`'s pattern table; add Linux-specific patterns (dpkg lock, dnf metadata, AUR build failures).
- Preserve the Windows-package audit-only behavior on WSL2.

Out of scope: Windows-side upgrade execution (still surfaced as manual `winget upgrade --all` guidance).

</details>

## Progress

| Phase | Milestone | Status | Completed |
|-------|-----------|--------|-----------|
| 1–6 (v1.0 phases) | v1.0 | Complete | 2026-04-17 → 2026-04-19 |
| 7–11 (v1.1 phases) | v1.1 | Complete (verified static) | 2026-05-07 |
| Security hardening | v1.2 | Complete | 2026-05-07 |
| Self-update + review findings | v1.2.1 / v1.2.2 | Complete | 2026-05-08 |
| Update advisor agents | v1.3 | Complete | 2026-05-11 |
| Codex review findings | v1.3.1 | Complete | 2026-05-13 |
| Fast discovery + synthesis | v1.4 | Complete (live-validated) | 2026-05-18 / 2026-05-27 |
| Single-shot orchestrator | v1.5 | Complete (shipped) | 2026-05-29 |
| Linux/WSL2 fast-path port | v1.6 | In review (contract-tested) | 2026-05-29 |
