---
phase: 03-wsl2-support
plan: "03"
subsystem: skills
tags: [wsl2, windows, winget, scoop, choco, update, package-managers]

# Dependency graph
requires:
  - phase: 03-wsl2-support-01
    provides: WSL2 OS_TYPE detection and banner pattern established across skills
provides:
  - WSL2 banner in update/SKILL.md Environment Detection section (fires before any step)
  - Windows package manager detection block in update/SKILL.md Step 2 (winget/scoop/choco via command -v)
  - Windows Packages row group in Step 3 Overview Table (audit only, WSL2 only)
  - Explicit audit-only note in Step 5 before upgrade table
  - Windows Packages row group in Step 6 Final Report (audit only, WSL2 only)
affects: [03-wsl2-support, 03-04, skills/update]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "WSL2 /mnt/c accessibility guard before Windows tool detection"
    - "command -v guard per Windows tool with informational fallback messages"
    - "Audit-only blockquote pattern for Windows tools: instruction prose instead of executable fences"
    - "Windows package rows labeled 'audit only' in Overview Table and Final Report"

key-files:
  created: []
  modified:
    - upkeep/skills/update/SKILL.md

key-decisions:
  - "Windows package managers detected via command -v + /mnt/c guard — never upgrade from WSL2 (UAC/permission implications)"
  - "Upgrade commands for winget/scoop/choco appear only in prose blockquote, never in executable bash fences"
  - "Step 5 upgrade table explicitly excludes winget/scoop/choco — audit-only note added before table"
  - "Step 6 Final Report shows Windows Packages group with audit-only status so skip is visible not silent"

patterns-established:
  - "Windows tool detection: /mnt/c mount guard first, then command -v per tool"
  - "Audit-only disclosure: blockquote with guidance text, never inside bash fence"

requirements-completed: [WSL-01, WSL-04]

# Metrics
duration: 3min
completed: "2026-04-17"
---

# Phase 03 Plan 03: Update skill WSL2 banner + Windows package manager audit (WSL-01, WSL-04)

**WSL2 banner added to update Environment Detection and Windows package managers (winget/scoop/choco) surfaced as audit-only rows in Step 2, Step 3, and Step 6 — no upgrade commands added**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-04-17T15:45:35Z
- **Completed:** 2026-04-17T15:48:04Z
- **Tasks:** 3
- **Files modified:** 1

## Accomplishments

- WSL2 banner bash fence inserted after Environment Detection block: prints `=== Running in WSL2 on Windows ===` when `$OS_TYPE = wsl2`
- allowed-tools frontmatter extended with `Bash(winget *)`, `Bash(scoop *)`, `Bash(choco *)` under WSL2 audit-only comment
- Step 2 Windows package manager detection block added: `$OS_TYPE = wsl2` guard + `/mnt/c` accessibility guard + per-tool `command -v` checks with `head -5` package list output
- Step 3 Overview Table extended with `── Windows Packages (WSL2 only — audit only) ──` row group (winget/scoop/choco rows)
- Step 5 explicit audit-only note added before upgrade table making clear winget/scoop/choco are not in the table
- Step 6 Final Report extended with `── Windows Packages (WSL2 only) ──` row group showing `ⓘ audit only` status per tool

## Task Commits

Each task was committed atomically:

1. **Task 1: Add WSL2 banner + winget/scoop/choco to allowed-tools** - `6d8acf4` (feat)
2. **Task 2: Add Windows package manager detection block to Step 2** - `ed23cf4` (feat)
3. **Task 3: Extend Step 3 table + Step 5 note + Step 6 report** - `0bb51ba` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `upkeep/skills/update/SKILL.md` — Three additive sets of changes:
  - Lines 62-64: three new allowed-tools entries (winget, scoop, choco)
  - Lines 131-138: WSL2 banner bash fence after Environment Detection
  - Lines 196-218: Windows package manager detection section between Step 2 and Step 3
  - Lines 238-244: Windows Packages row group inside Step 3 Overview Table fence
  - Lines 246-248: clarifying paragraph after Step 3 table
  - Lines 274-276: audit-only note before Step 5 upgrade table
  - Lines 307-312: Windows Packages row group inside Step 6 Final Report fence
  - Lines 315: clarifying sentence after Step 6 omit paragraph

## Decisions Made

- Windows package managers detected via `command -v` with `/mnt/c` mount guard first — avoids any PATH resolution issues if Windows drive is not mounted
- Upgrade commands (`winget upgrade`, `scoop update`, `choco upgrade`) appear ONLY inside a prose blockquote, never in an executable bash fence — preserves the skill's "never run upgrade without confirmation" posture
- Step 5 upgrade table explicitly excludes winget/scoop/choco with a dedicated audit-only note paragraph — machine-checkable: `grep -E "^\| (winget|scoop|choco) \|"` returns zero matches
- Step 6 shows Windows Packages with `ⓘ audit only` status making the skip visible, not silent

## Verification Results

Post-execution grep checks (all passing):

| Check | Expected | Actual |
|-------|----------|--------|
| `grep -c "Running in WSL2 on Windows"` | 1 | 1 |
| `grep -c "/mnt/c"` | ≥1 | 2 |
| `grep -cE "Bash\((winget\|scoop\|choco) \*\)"` | 3 | 3 |
| `grep -cE "command -v (winget\|scoop\|choco)"` | 3 | 3 |
| `grep -E "^\| (winget\|scoop\|choco) \|"` | 0 matches | 0 matches (PASS) |
| `grep -c "^\`\`\`"` (even number) | even | 14 (PASS) |

Note: `grep -c "sudo"` returns 1 (pre-existing `- Never run sudo` rule line, not introduced by this plan).

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- WSL-01 and WSL-04 satisfied for the update skill
- Phase 03 plan 03 complete — all three WSL2 support plans (03-01, 03-02, 03-03) are now done
- update skill now surfaces Windows package managers as audit-only rows with clear guidance for users to upgrade from a Windows shell

---
*Phase: 03-wsl2-support*
*Completed: 2026-04-17*
