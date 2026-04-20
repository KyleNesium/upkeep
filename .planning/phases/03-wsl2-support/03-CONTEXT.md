# Phase 3: WSL2 Support - Context

**Gathered:** 2026-04-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Add WSL2-specific additions to all 5 upkeep skills. Phase 2 added Linux cleanup content — Phase 3 adds the WSL2 layer that fires when `$OS_TYPE` is `wsl2`. Delivers: (1) environment banner across all skills, (2) Windows temp file cleanup via /mnt/c/ in cleandeep, (3) Windows npm/pip cache audit in cleandeep, (4) Windows package manager detection in update.

</domain>

<decisions>
## Implementation Decisions

### All implementation choices are at Claude's discretion — pure infrastructure phase

Phase 3 extends Phase 2's patterns to WSL2. All implementation choices follow established patterns:
- Use `$OS_TYPE = "wsl2"` already set by Environment Detection snippet
- Banner: add "Running in WSL2 on Windows" header to each skill's Environment Detection section — fires when `$OS_TYPE = "wsl2"` before any phase runs
- Windows paths: always via `/mnt/c/` bridge — no native Windows commands
- WSL-02 (Windows temp): `du -sh /mnt/c/Users/$USER/AppData/Local/Temp/` → approval gate → `rm -rf` on approval
- WSL-03 (Windows npm/pip caches): `du -sh` on `/mnt/c/Users/$USER/AppData/Roaming/npm-cache/` and `/mnt/c/Users/$USER/AppData/Local/pip/Cache/` → size audit + optional cleanup
- WSL-04 (Windows pkg managers): `command -v winget`, `command -v scoop.cmd`, `command -v choco` — detect and report, no removal
- Never sudo on Windows paths
- Graceful fallback if /mnt/c/ is not accessible (WSL2 without Windows C: mounted)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `$OS_TYPE = "wsl2"` — already set by Environment Detection snippet in all 5 skills (Phase 1)
- Existing approval-gate pattern from Phase 2 macOS/Linux phases — mirror for Windows cleanup
- Phase 2 Linux guards: `elif [ "$OS_TYPE" = "linux" ] || [ "$OS_TYPE" = "wsl2" ]` — WSL2 already runs Linux cleanup

### Established Patterns
- Banner pattern: output a one-line header before phases when WSL2 detected (no prompt, just info)
- Phase structure: show sizes → dry-run → ask user → execute with approval
- Never sudo — applies to /mnt/c/ paths too
- `command -v <tool>` guard before using any optional tool

### Integration Points
- All 5 SKILL.md files: add WSL2 banner to Environment Detection section
- cleandeep/SKILL.md: add new Phase 17 (Windows Temp) and Phase 18 (Windows npm/pip) at end
- update/SKILL.md: add WSL2 Windows package manager detection block

</code_context>

<specifics>
## Specific Ideas

WSL2-specific implementations:
- Banner: `echo "=== Running in WSL2 on Windows ==="`  printed after OS detection in Environment Detection section
- Windows temp: `du -sh /mnt/c/Users/"$USER"/AppData/Local/Temp/ 2>/dev/null || echo "(Windows temp not accessible — /mnt/c/ may not be mounted)"`
- Windows npm: `/mnt/c/Users/"$USER"/AppData/Roaming/npm-cache/`
- Windows pip: `/mnt/c/Users/"$USER"/AppData/Local/pip/Cache/`
- Windows package managers: `winget list 2>/dev/null | head -5`, `scoop list 2>/dev/null | head -5`, `choco list 2>/dev/null | head -5`
- /mnt/c/ accessibility guard: `if [ -d "/mnt/c" ]; then ... else echo "(Windows C: not mounted — skipping)"; fi`

</specifics>

<deferred>
## Deferred Ideas

- WSL2 Recycle Bin audit → v2 (WSL-V2-01)
- WSL2 distro export/import size → v2 (WSL-V2-02)
- winget upgrade / scoop update / choco upgrade → deferred (audit only in Phase 3; upgrades may belong in Phase 4 update skill)

</deferred>

---
*Phase: 03-wsl2-support*
*Context gathered: 2026-04-17 via autonomous smart discuss (infrastructure phase)*
