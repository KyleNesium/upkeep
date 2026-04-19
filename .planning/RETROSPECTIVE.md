# Retrospective

## Milestone: v1.0 — Linux & WSL2 Cross-Platform Support

**Shipped:** 2026-04-19  
**Phases:** 6 | **Plans:** 17 | **Timeline:** 4 days (2026-04-16 → 2026-04-19)

### What Was Built

- OS detection snippet injected into all 5 SKILL.md files — `$OS_TYPE`, `$OS_DISTRO`, `$PKG_MGR` resolved at phase entry
- Linux cleanup suite (apt/dnf/pacman cache, journald vacuum, ~/.cache sweep, snap/flatpak orphans) in cleandeep, cleanquick, audit
- WSL2 detection banner + Windows-side cleanup via `/mnt/c/` bridge (Temp, npm cache, pip cache)
- Linux upgrade paths in update skill (apt/dnf/pacman + snap + flatpak); Windows pkg audit in WSL2 (winget/scoop/choco, audit-only)
- Full umbrella router parity via gap closure Phases 5+6 — all 5 integration gaps (MISS-1 through MISS-5) closed
- README, badges, and SKILL.md descriptions updated to reflect macOS 14+ / Linux / WSL2

### What Worked

- **Phase-by-phase verification** caught the umbrella gap early — the v1.0 audit surfaced MISS-1 through MISS-5 before the milestone was declared complete
- **Additive-only constraint** ("never replace, only guard") kept macOS regressions at zero — every change wrapped in an OS guard
- **Port-from-sub-skill pattern** for Phases 5+6 was safe and fast — no new logic invented, content verified against known-good source
- **`command -v` snap/flatpak gating** (not OS_TYPE) correctly handles edge cases like Linuxbrew on macOS without over-specifying

### What Was Inefficient

- **Umbrella gap discovered post-execution**: Phases 1–4 all targeted sub-skills exclusively. The umbrella router (`upkeep/skills/upkeep/SKILL.md`) was self-contained and needed its own pass. Two additional phases (5+6) were required to close the gap — this could have been anticipated in the initial roadmap.
- **Phase 5 missing VERIFICATION.md**: Phase 5 was executed via direct agent spawn, bypassing the `gsd:execute-phase` workflow which auto-runs `gsd-verifier`. The verification had to be spawned inline during the audit pass.
- **Summary one_liner field absent**: SUMMARY.md files lacked a `one_liner` frontmatter field, causing `gsd-tools summary-extract` to return null for all files. Accomplishments had to be written manually.

### Patterns Established

- **Umbrella-first rule**: In future multi-file skills, include the umbrella router in every phase plan — not as an afterthought. It doesn't inherit sub-skill changes.
- **OS guard position**: Guards placed BEFORE `command -v` checks so macOS falls through to existing tool-availability checks unchanged.
- **sudo as Manual Steps**: Upgrade commands that require sudo appear only in prose blockquote/Manual Steps sections, never in executable bash fences.
- **WSL2 `/mnt/c` outer guard**: All Windows-side operations wrapped in `if [ -d "/mnt/c" ]` outer guard to prevent path stat errors surfacing to users.

### Key Lessons

- **Umbrella routers need their own execution plan** — they don't inherit from sub-skills
- **Phase verifications should always go through execute-phase workflow** to ensure VERIFICATION.md is auto-created
- **Add `one_liner` to SUMMARY.md template** so gsd-tools can extract accomplishments automatically
- **Audit before complete** paid off — caught a high-severity gap (MISS-2, MISS-5) that would have shipped broken Linux support

### Cost Observations

- Sessions: Multiple (context-compacted mid-milestone)
- Notable: Phase 6 had 87 edit operations in one plan (the umbrella Update Mode is large); still completed in one agent execution

---

## Cross-Milestone Trends

| Metric | v1.0 |
|--------|------|
| Phases | 6 |
| Plans | 17 |
| Timeline | 4 days |
| Audit gaps found | 5 |
| Audit gaps closed | 5 |
| Regression count | 0 |
