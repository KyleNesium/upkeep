---
name: upkeep:cleanquick
version: 1.1.0-dev
author: KyleNesium
description: |
  Fast macOS cache sweep: Homebrew, dev tool caches, build artifacts (report),
  Electron app caches, and Trash. Skips the slower discovery scans. Good for
  monthly maintenance. Typical recovery: 1-5GB.
  Use when: "quick clean", "fast cleanup", "just caches", "routine cleanup",
  "quick sweep", "just clean caches", "quick mac cleanup".
allowed-tools:
  # Read-only discovery / queries
  - Bash(diskutil *)
  - Bash(df *)
  - Bash(du *)
  - Bash(ls *)
  - Bash(stat *)
  - Bash(find *)
  - Bash(sw_vers *)
  - Bash(echo *)
  - Bash(date *)
  - Bash(touch *)
  - Bash(command *)
  - Bash(which *)
  - Bash(pgrep *)
  # OS detection (cross-platform)
  - Bash(uname *)
  - Bash(lsb_release *)
  - Bash(lsblk *)
  - Bash(cat *)
  # Text processing for pipelines
  - Bash(sort *)
  - Bash(head *)
  - Bash(tail *)
  - Bash(grep *)
  - Bash(awk *)
  - Bash(sed *)
  - Bash(cut *)
  - Bash(wc *)
  # Homebrew (audit + removal with approval)
  - Bash(brew *)
  # Package managers (cache / cleanup commands)
  - Bash(npm *)
  - Bash(yarn *)
  - Bash(pnpm *)
  - Bash(bun *)
  - Bash(pip *)
  - Bash(pipx *)
  - Bash(uv *)
  - Bash(go *)
  - Bash(cargo *)
  - Bash(pod *)
  - Bash(gem *)
  # Filesystem mutation (approval-gated; never sudo)
  - Bash(rm *)
  - Read
  - Glob
  - Grep
  # Linux system tools
  - Bash(systemctl *)
  - Bash(journalctl *)
  # Linux package managers
  - Bash(apt *)
  - Bash(dnf *)
  - Bash(pacman *)
  - Bash(snap *)
  - Bash(flatpak *)
---

# /upkeep:cleanquick — Quick macOS Cache Sweep

You are a macOS system cleanup specialist. Run the quick phases only: 1, 2, 3, 8, 11, 13.
Report sizes, ask before removing. Never run sudo. Tag each phase header with `(Quick)`.

## Phase 1: Baseline (Quick)

Record starting disk state for before/after comparison.

```bash
echo "=== Disk ===" && diskutil info / 2>/dev/null | grep -E "Free|Available|Purgeable" || df -h / | tail -1
echo "=== macOS ===" && sw_vers
echo "=== Homebrew ===" && brew --version 2>/dev/null || echo "not installed"
```

Capture "Available" and "Purgeable" from `diskutil info`. APFS volumes have
purgeable space that `df` doesn't distinguish — use `diskutil` for accurate
before/after. Fall back to `df` if unavailable.

Then run a passive update check (at most once per 24h, silent on all failures):

```bash
if [ "${UPKEEP_SKIP_UPDATE_CHECK:-}" != "1" ] && command -v git >/dev/null 2>&1; then
  _CHECK_FILE="${CLAUDE_SKILL_DIR}/../../../.last-update-check"
  _LAST=$(stat -f %m "$_CHECK_FILE" 2>/dev/null || echo 0)
  if [ $(( $(date +%s) - $_LAST )) -gt 86400 ]; then
    git -C "${CLAUDE_SKILL_DIR}/../../.." fetch --tags --quiet origin main 2>/dev/null
    touch "$_CHECK_FILE" 2>/dev/null
    _BEHIND=$(git -C "${CLAUDE_SKILL_DIR}/../../.." log HEAD..origin/main --oneline \
      2>/dev/null | wc -l | tr -d ' ')
    [ "${_BEHIND:-0}" -gt 0 ] && \
      echo "ℹ upkeep update available — run: /upkeep:update"
  fi
fi
```

If the nudge fires, display it once at the top before phase output.

## Phase 2: Homebrew Audit (Quick)

```bash
command -v brew >/dev/null 2>&1 && echo "OK" || echo "Phase 2 skipped — brew not installed"
```
If skipped, skip this entire phase.

1. `brew outdated` — outdated packages
2. `brew cleanup --dry-run` — stale downloads, old portable-ruby versions
3. `brew autoremove --dry-run` — orphan dependencies. **Always display full
   dry-run output verbatim** (never truncate). If empty: "No orphan dependencies
   to remove." If packages listed, show all and ask confirmation before
   running live `brew autoremove`.
4. `brew doctor 2>&1 | grep -iE "deprecated|warning|error"` — health issues

Actions (with approval):
- `brew cleanup` — remove stale downloads (safe, reclaims space)
- `brew autoremove` — only after showing dry-run and receiving confirmation
- `brew upgrade` — **only offer AFTER cleanup completes**, as a separate
  optional step with its own approval prompt. Never bundle with cleanup.

## Phase 3: Dev Tool Caches (Quick)

**Discovery-based.** Don't just check a hardcoded list. Scan and report.

### Step 1: Known cache locations

Read the cache table from ${CLAUDE_SKILL_DIR}/../upkeep/reference/dev-tool-caches.md.
Check each listed location. Report size. Skip any that don't exist.

### Step 2: Discovery scan

```bash
du -sh ~/.cache/*/ 2>/dev/null | sort -rh | head -15
du -sh ~/Library/Caches/*/ 2>/dev/null | sort -rh | head -15
```

Report anything over 50MB not in the known list.

Dev caches are safe to clear when online — they rebuild on next install/build.
Note: Go modules (`~/go/pkg/mod/`) and cargo registry require network to rebuild.
If a tool's CLI binary isn't installed, skip its clear command and offer
`rm -rf` on the directory instead.
Present the total and ask for approval before clearing.

## Phase 8: Project Build Artifacts (Quick — report only)

Discover project directories:

```bash
for dir in ~/workspace ~/dev ~/Developer ~/code ~/src ~/projects ~/repos ~/Documents; do
  [ -d "$dir" ] && echo "FOUND: $dir"
done
```

Note: `~/Documents` may sync via iCloud — report sizes but do not offer removal.
If none found, scan `~` with maxdepth 5.

```bash
find <DIRS> -maxdepth 4 -name "node_modules" -type d -exec du -sh {} + 2>/dev/null | sort -rh
find <DIRS> -maxdepth 4 \( -name ".venv" -o -name "venv" \) -type d -exec du -sh {} + 2>/dev/null | sort -rh
find <DIRS> -maxdepth 4 \( -name ".next" -o -name "dist" -o -name "build" -o -name "out" -o -name "target" -o -name "__pycache__" -o -name ".mypy_cache" -o -name ".pytest_cache" -o -name ".turbo" -o -name ".nx" -o -name "Pods" -o -name ".build" -o -name "coverage" \) -type d -exec du -sh {} + 2>/dev/null | sort -rh | head -20
```

**Quick mode: report totals only — do not offer removal.** For cleanup, run `/upkeep:cleandeep`.

## Phase 11: Electron App Caches (Quick)

```bash
find ~/Library/Application\ Support -maxdepth 5 \
  -not -path "*/Claude/*" -not -path "*/Claude" \
  \( -name "Cache" -o -name "Code Cache" -o -name "Service Worker" -o -name "CachedData" -o -name "CachedExtension*" -o -name "PersistentCache" -o -name "GPUCache" \) \
  -type d -exec du -sh {} + 2>/dev/null | sort -rh | head -15
```

Only show caches over 50MB. Before offering to clear, check if app is running:
`pgrep -x "<AppName>" >/dev/null 2>&1`
If running: "Electron cache skipped — <AppName> is running". Do NOT use `pgrep -f`.
Only offer clearing for confirmed-not-running apps.

## Phase 13: Trash (Quick)

```bash
du -sh ~/.Trash/ 2>/dev/null
```

Offer: `rm -rf ~/.Trash/*` or suggest Finder (Cmd+Shift+Delete).

## Reporting

### Per-phase

After each phase, report findings in a short table. Ask before action.
Batch removals by phase — don't ask per-file unless ambiguous.

### Final Summary

```
## Quick Clean Report

| # | Category | Items | Reclaimable | Status |
|---|----------|-------|-------------|--------|
| 2 | Homebrew | ... | ...MB | Cleaned / Skipped |
| 3 | Dev caches | ... | ...GB | Cleaned / Skipped |
| 8 | Build artifacts | ... | ...GB | Report only |
| 11| Electron caches | ... | ...MB | Cleaned / Skipped |
| 13| Trash | ... | ...GB | Cleaned / Skipped |
| **Total** | | | **...GB** | |
```

### Before/After

```bash
diskutil info / 2>/dev/null | grep -E "Free|Available|Purgeable" || df -h / | tail -1
```

```
Disk before: XXX available (YYY purgeable)
Disk after:  XXX available (YYY purgeable)
Reclaimed:   ~ZZZ
```

macOS keeps recently deleted data as "purgeable" — Finder may not show freed
space immediately because it reclaims on demand.

## Rules

- NEVER remove data for apps currently installed in /Applications
- NEVER touch `~/Library/Application Support/Claude/` or `~/.claude/`
- NEVER remove Apple system directories (`com.apple.*`)
- ALWAYS report sizes before removing anything
- ALWAYS ask before removing brew packages or ambiguous items
- For caches: batch approval is fine ("clear all dev caches?")
- Never execute sudo — surface the exact command in a fenced bash block
- Build artifacts (Phase 8): report only — never offer removal in Quick mode
- Track cumulative space reclaimed, report total at the end
