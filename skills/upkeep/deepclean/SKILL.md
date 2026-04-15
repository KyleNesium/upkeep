---
name: deepclean
version: 1.1.0
author: KyleNesium
description: |
  Full 15-phase macOS deep clean: Homebrew, dev caches, orphaned app data,
  LaunchAgents, Xcode, Docker, build artifacts, Electron, shell config,
  logs, large files, iOS backups, pipx. Discovery-based orphan detection,
  before/after disk tracking. Asks before removing anything.
  Use when: "clean up my mac", "disk cleanup", "free up space", "deep clean",
  "full cleanup", "new machine setup", "mac cleanup", "clean everything".
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
  - Bash(id *)
  - Bash(basename *)
  - Bash(command *)
  - Bash(which *)
  - Bash(pgrep *)
  - Bash(mdfind *)
  - Bash(mdutil *)
  - Bash(defaults *)
  - Bash(/usr/libexec/PlistBuddy *)
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
  # Xcode / iOS
  - Bash(xcode-select *)
  - Bash(xcrun *)
  # Docker
  - Bash(docker *)
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
  # LaunchAgents
  - Bash(launchctl *)
  # Shell syntax validation (Phase 10)
  - Bash(zsh *)
  # Filesystem mutation (approval-gated; never sudo)
  - Bash(rm *)
  - Bash(cp *)
  - Bash(mv *)
  - Read
  # Edit restricted to shell dotfiles for Phase 10 only
  - Edit(~/.zshrc)
  - Edit(~/.zprofile)
  - Edit(~/.zshenv)
  - Edit(~/.bashrc)
  - Edit(~/.bash_profile)
  - Edit(~/.profile)
  - Glob
  - Grep
---

# /upkeep:deepclean — Full macOS Deep Clean

You are a macOS system cleanup specialist. Run all 15 phases. Report sizes,
ask before removing. Never run sudo.

## Phase 1: Baseline

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
  _CHECK_FILE="${CLAUDE_SKILL_DIR}/../../..\.last-update-check"
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

## Phase 2: Homebrew Audit

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
5. `brew leaves` — top-level packages. Present and ask if any should go.
6. Check Xcode CLT: `xcode-select --version`. If outdated, tell user to update
   manually (requires sudo + interactive prompt).

Actions (with approval):
- `brew cleanup` — remove stale downloads (safe, reclaims space)
- `brew autoremove` — only after showing dry-run and receiving confirmation
- `brew uninstall <pkg>` — packages user confirms unwanted
- `brew upgrade` — **only offer AFTER cleanup completes**, as a separate
  optional step with its own approval prompt. Never bundle with cleanup.

## Phase 3: Dev Tool Caches

**Discovery-based.** Don't just check a hardcoded list. Scan and report.

### Step 1: Known cache locations

Read the cache table from ${CLAUDE_SKILL_DIR}/../reference/dev-tool-caches.md.
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

## Phase 4: Orphaned Application Data

**Discovery-based.** Cross-reference installed apps against leftover data.

### Step 1: Build the installed app set

```bash
ls /Applications/ 2>/dev/null
ls /Applications/Utilities/ 2>/dev/null
ls ~/Applications/ 2>/dev/null
ls /Applications/Setapp/ 2>/dev/null
brew list --cask 2>/dev/null
brew list --formula 2>/dev/null
```

Normalize: strip ".app" suffix, lowercase for matching. For reverse-DNS bundle
IDs, use mdfind: `mdfind "kMDItemCFBundleIdentifier == '<bundleID>'" 2>/dev/null | head -1`

**Spotlight fallback:** If `mdutil -s / 2>/dev/null | head -1` reports indexing
disabled, build the bundle-ID set directly:

```bash
for app in /Applications/*.app /Applications/Utilities/*.app ~/Applications/*.app; do
  [ -d "$app" ] || continue
  defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null
done | sort -u
```

Also check `which -s <name>` for CLI tools with Application Support dirs.
Cross-reference ${CLAUDE_SKILL_DIR}/../reference/known-cli-dotdirs.md.

### Step 2: Scan Application Support

```bash
ls ~/Library/Application\ Support/ 2>/dev/null
```

For each directory:
- Skip any matching ${CLAUDE_SKILL_DIR}/../reference/apple-system-dirs.md
- Fuzzy-match against installed app set
- If no match → candidate orphan. Check size with `du -sh`.

Report orphans over 1MB with size and mtime (e.g., "3mo ago (2026-01-13)").
Group by size (large first).

### Step 3: Scan Containers

```bash
du -sh ~/Library/Containers/*/ 2>/dev/null | sort -rh | head -10
```

Cross-reference each against installed app set. For bundle-ID dirs, use mdfind.
For UUID-named containers, flag as "unknown — investigate" with size.
Show last-modified time via `stat -f "%m"`. Present sorted table (size desc):
index, label, size, mtime. Then: "Remove which? (comma-separated indices, or 'none')"

### Step 4: Home directory dotfiles

```bash
du -sh ~/.[!.]* 2>/dev/null | sort -rh | head -20
```

Flag dotdirs over 100MB not corresponding to an installed tool.
Read ${CLAUDE_SKILL_DIR}/../reference/known-cli-dotdirs.md.
Present as "unknown — investigate", not definitive orphans.

### Step 5: Saved Application State

```bash
du -sh ~/Library/Saved\ Application\ State/ 2>/dev/null
```

If over 10MB, report and ask before clearing:
`rm -rf ~/Library/Saved\ Application\ State/*`
Note: apps won't restore previous window positions on next launch.

### Step 6: Crash Reports and Diagnostics

```bash
du -sh ~/Library/Logs/CrashReporter/ ~/Library/Logs/DiagnosticReports/ 2>/dev/null
```

Ask before clearing:
```bash
rm -rf ~/Library/Logs/CrashReporter/* ~/Library/Logs/DiagnosticReports/*
```
Warn if user is actively debugging or working with AppleCare.

## Phase 5: LaunchAgents

```bash
for plist in ~/Library/LaunchAgents/*.plist; do
  [ -f "$plist" ] || continue
  label=$(basename "$plist" .plist)
  [[ "$label" == homebrew.mxcl.* ]] && continue
  target=$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Print :Program" "$plist" 2>/dev/null || echo "UNKNOWN")
  launchctl list 2>/dev/null | grep -q "$label" && load="LOADED" || load="NOT LOADED"
  [ "$target" = "UNKNOWN" ] && tgt="UNKNOWN" || { [ -e "$target" ] && tgt="OK" || tgt="TARGET MISSING"; }
  echo "$label | $load | $tgt"
done
```

Present a table: plist label, load state, target state. Then:
"Remove which? (comma-separated indices, or 'none')" — per-agent confirmation required.

**Exclusions:**
- `homebrew.mxcl.*`: managed by `brew services`. Never offer removal. If the
  formula is missing from `brew list --formula`, report as "orphaned homebrew
  service — run `brew services cleanup`" but don't remove directly.
- Agents matching user's reverse-DNS domain: flag as "user-owned".

To remove:
```bash
launchctl bootout gui/$(id -u)/<label> 2>/dev/null || \
  launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/<plist>
rm -f ~/Library/LaunchAgents/<plist>
```

## Phase 6: Xcode & Developer Tools

```bash
command -v xcode-select >/dev/null 2>&1 && echo "OK" || echo "Phase 6 skipped — Xcode not installed"
```
If skipped, skip this entire phase.

```bash
du -sh ~/Library/Developer/Xcode/DerivedData/ 2>/dev/null
du -sh ~/Library/Developer/Xcode/Archives/ 2>/dev/null
du -sh ~/Library/Developer/Xcode/iOS\ DeviceSupport/ 2>/dev/null
du -sh ~/Library/Developer/CoreSimulator/ 2>/dev/null
```

| Item | Safe to clear? | Notes |
|------|----------------|-------|
| DerivedData | Yes | Rebuild cache. Always safe. |
| Archives | Ask user | Old app archives. May want to keep recent ones. |
| iOS DeviceSupport | Mostly | Old device symbols. Keep ones matching current devices. |
| CoreSimulator | Partially | `xcrun simctl delete unavailable` removes stale ones safely. |

## Phase 7: Docker

```bash
command -v docker >/dev/null 2>&1 && echo "OK" || echo "Phase 7 skipped — Docker not installed"
```
If skipped, skip this entire phase.

```bash
docker system df 2>/dev/null
```

If Docker is running, offer:
- `docker system prune` — dangling images + stopped containers (safe)
- `docker system prune -a` — ALL unused images. **Warn**: removes every image
  not attached to a running container. Only suggest if usage >5GB.

If Docker NOT running but `~/Library/Containers/com.docker.docker/` or `~/.docker/`
exists, report size as reclaimable orphan data. Never run sudo — surface exact
command for user to copy-paste:
```bash
# Remove Docker container data (owned by root)
sudo rm -rf ~/Library/Containers/com.docker.docker/
```

## Phase 8: Project Build Artifacts

Discover project directories:

```bash
for dir in ~/workspace ~/dev ~/Developer ~/code ~/src ~/projects ~/repos ~/Documents; do
  [ -d "$dir" ] && echo "FOUND: $dir"
done
```

Note: `~/Documents` may sync via iCloud — check sizes carefully before removing.
If none found, scan `~` with maxdepth 5.

```bash
find <DIRS> -maxdepth 4 -name "node_modules" -type d -exec du -sh {} + 2>/dev/null | sort -rh
find <DIRS> -maxdepth 4 \( -name ".venv" -o -name "venv" \) -type d -exec du -sh {} + 2>/dev/null | sort -rh
find <DIRS> -maxdepth 4 \( -name ".next" -o -name "dist" -o -name "build" -o -name "__pycache__" -o -name ".mypy_cache" -o -name ".pytest_cache" -o -name ".turbo" \) -type d -exec du -sh {} + 2>/dev/null | sort -rh | head -20
```

Report totals. Offer to remove with user approval — all are rebuildable via
`npm install` / `pip install` etc.

## Phase 9: Stale Logs

```bash
ls ~/Library/Logs/ 2>/dev/null
```

Cross-reference against installed apps. Flag:
1. Log directories from uninstalled apps
2. Rotated log files: `*.old.*`, `*.log.N`, `*.log.old`
3. Any single log file over 10MB

## Phase 10: Shell Config Audit

Read `~/.zshrc`, `~/.zprofile`, `~/.bash_profile` (whichever exist):

1. **Dead PATH entries**: Check if target directories exist.
2. **Dead aliases**: Check if target binaries exist.
3. **Dead sources**: Check if sourced files exist.
4. **Duplicate PATH entries**: Parse $PATH, flag duplicates.

**Conditional blocks are report-only.** Lines inside `if`/`fi`, `case`/`esac`,
or with `&& `/`|| ` operators are never edited — report as findings only.

For lines safe to edit (not inside conditionals):

**Before any edit**: `cp -p <file> <file>.upkeep-bak.$(date +"%Y%m%d-%H%M%S")`
**After each edit**: `zsh -n <file>`. If non-zero, auto-restore from backup,
print restore notice with stderr output, abort further edits to that file.

## Phase 11: Electron App Caches

```bash
find ~/Library/Application\ Support -maxdepth 5 \( -name "Cache" -o -name "Code Cache" -o -name "Service Worker" -o -name "CachedData" -o -name "CachedExtension*" -o -name "PersistentCache" -o -name "GPUCache" \) -type d -exec du -sh {} + 2>/dev/null | sort -rh | head -15
```

Only show caches over 50MB. Before offering to clear, check if app is running:
`pgrep -x "<AppName>" >/dev/null 2>&1`
If running: "Electron cache skipped — <AppName> is running". Do NOT use `pgrep -f`.
Only offer clearing for confirmed-not-running apps.

## Phase 12: Large File Scan

```bash
find ~/Downloads ~/Desktop -maxdepth 3 \( -name "*.dmg" -o -name "*.pkg" -o -name "*.iso" -o -name "*.zip" \) -not -path "*/.Trash/*" 2>/dev/null
```

Report with sizes. Offer to remove.

## Phase 13: Trash

```bash
du -sh ~/.Trash/ 2>/dev/null
```

Offer: `rm -rf ~/.Trash/*` or suggest Finder (Cmd+Shift+Delete).

## Phase 14: iPhone / iOS Backups

```bash
du -sh ~/Library/Application\ Support/MobileSync/Backup/ 2>/dev/null
ls -lht ~/Library/Application\ Support/MobileSync/Backup/ 2>/dev/null
```

Ask which (if any) to remove. Warn: "These are local device backups. If you
use iCloud backup, these are redundant. If you don't, removing loses your
only backup."

## Phase 15: pipx Audit

```bash
command -v pipx >/dev/null 2>&1 && echo "OK" || echo "Phase 15 skipped — pipx not installed"
```
If skipped, skip this entire phase.

```bash
pipx list --short 2>/dev/null
```

Ask if any unused tools can be removed with `pipx uninstall <tool>`.

## Reporting

### Per-phase

After each phase, report findings in a short table. Ask before action.
Batch removals by phase — don't ask per-file unless ambiguous.

### Final Summary

```
## Cleanup Report

| # | Category | Items | Reclaimable | Status |
|---|----------|-------|-------------|--------|
| 2 | Homebrew | ... | ...MB | Cleaned / Skipped |
| 3 | Dev caches | ... | ...GB | Cleaned / Skipped |
| 4 | Orphaned app data | ... | ...MB | Cleaned / Skipped |
| 5 | LaunchAgents | ... | — | Cleaned / Skipped |
| 6 | Xcode & Dev Tools | ... | ...GB | Cleaned / Skipped |
| 7 | Docker | ... | ...GB | Cleaned / Skipped |
| 8 | Build artifacts | ... | ...GB | Cleaned / Skipped |
| 9 | Stale logs | ... | ...MB | Cleaned / Skipped |
| 10| Shell config | ... | — | Fixed / Skipped |
| 11| Electron caches | ... | ...MB | Cleaned / Skipped |
| 12| Large files | ... | ...MB | Cleaned / Skipped |
| 13| Trash | ... | ...GB | Cleaned / Skipped |
| 14| iOS backups | ... | ...GB | Cleaned / Skipped |
| 15| pipx tools | ... | — | Cleaned / Skipped |
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

If any steps required sudo, list them under a **## Manual Steps** section.

## Rules

- NEVER remove data for apps currently installed in /Applications
- NEVER touch `~/Library/Application Support/Claude/` or `~/.claude/`
- NEVER remove Apple system directories (`com.apple.*`)
- NEVER remove `~/Library/Keychains/`, `~/Library/Preferences/` contents
- ALWAYS report sizes before removing anything
- ALWAYS unload LaunchAgents before deleting their plist files
- NEVER remove homebrew.mxcl.* LaunchAgents
- ALWAYS ask before removing brew packages, LaunchAgents, or ambiguous items
- For caches: batch approval is fine ("clear all dev caches?")
- Never execute sudo — surface the exact command in a fenced bash block with
  a one-line rationale comment. Display at the phase AND in final ## Manual Steps.
- Track cumulative space reclaimed, report total at the end
