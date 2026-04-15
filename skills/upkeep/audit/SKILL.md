---
name: audit
version: 1.1.0
author: KyleNesium
description: |
  Full 15-phase macOS disk audit — report only, no changes made.
  Discovers orphaned app data, stale caches, dead LaunchAgents, Xcode/Docker
  bloat, build artifacts, Electron caches, shell config issues, large files,
  iOS backups, and pipx tools. Reports sizes and findings, never removes.
  Use when: "audit my mac", "scan my mac", "what's taking up space",
  "report only", "just check", "don't remove anything", "what can I clean",
  "what's using space".
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
  # Package managers / tools — query commands only
  - Bash(brew *)
  - Bash(xcode-select *)
  - Bash(xcrun *)
  - Bash(docker *)
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
  - Bash(launchctl *)
  - Read
  - Glob
  - Grep
---

# /upkeep:audit — Full macOS Disk Audit

You are a macOS system auditor. Run all 15 phases. **Report findings and sizes
only — never offer to remove, clean, modify, or take any action.** This is a
read-only scan. The goal is a complete picture of what's reclaimable.

## Phase 1: Baseline

```bash
echo "=== Disk ===" && diskutil info / 2>/dev/null | grep -E "Free|Available|Purgeable" || df -h / | tail -1
echo "=== macOS ===" && sw_vers
echo "=== Homebrew ===" && brew --version 2>/dev/null || echo "not installed"
```

Capture "Available" and "Purgeable" from `diskutil info`.

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

## Phase 2: Homebrew Audit

```bash
command -v brew >/dev/null 2>&1 && echo "OK" || echo "Phase 2 skipped — brew not installed"
```
If skipped, skip this entire phase.

Report:
1. `brew outdated` — count and list outdated packages
2. `brew cleanup --dry-run` — size of stale downloads
3. `brew autoremove --dry-run` — orphan dependency count
4. `brew doctor 2>&1 | grep -iE "deprecated|warning|error"` — health issues
5. `brew leaves` — top-level packages (for awareness)
6. `xcode-select --version` — CLT version

## Phase 3: Dev Tool Caches

### Step 1: Known cache locations

Read the cache table from ${CLAUDE_SKILL_DIR}/../reference/dev-tool-caches.md.
Check each listed location. Report size. Skip any that don't exist.

### Step 2: Discovery scan

```bash
du -sh ~/.cache/*/ 2>/dev/null | sort -rh | head -15
du -sh ~/Library/Caches/*/ 2>/dev/null | sort -rh | head -15
```

Report anything over 50MB not in the known list.

## Phase 4: Orphaned Application Data

### Step 1: Build the installed app set

```bash
ls /Applications/ 2>/dev/null
ls /Applications/Utilities/ 2>/dev/null
ls ~/Applications/ 2>/dev/null
ls /Applications/Setapp/ 2>/dev/null
brew list --cask 2>/dev/null
brew list --formula 2>/dev/null
```

Normalize: strip ".app" suffix, lowercase. For reverse-DNS bundle IDs, use:
`mdfind "kMDItemCFBundleIdentifier == '<bundleID>'" 2>/dev/null | head -1`

**Spotlight fallback:** If `mdutil -s / 2>/dev/null | head -1` reports indexing
disabled, build the bundle-ID set directly:

```bash
for app in /Applications/*.app /Applications/Utilities/*.app ~/Applications/*.app; do
  [ -d "$app" ] || continue
  defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null
done | sort -u
```

Cross-reference ${CLAUDE_SKILL_DIR}/../reference/known-cli-dotdirs.md for CLI tools.

### Step 2: Scan Application Support

```bash
ls ~/Library/Application\ Support/ 2>/dev/null
```

Skip entries matching ${CLAUDE_SKILL_DIR}/../reference/apple-system-dirs.md.
Report orphan candidates over 1MB with size and mtime (e.g., "3mo ago (2026-01-13)").

### Step 3: Scan Containers

```bash
du -sh ~/Library/Containers/*/ 2>/dev/null | sort -rh | head -10
```

Report table: index, label, size, mtime. Flag UUID-named containers as "unknown — investigate".

### Step 4: Home directory dotfiles

```bash
du -sh ~/.[!.]* 2>/dev/null | sort -rh | head -20
```

Flag dotdirs over 100MB not corresponding to an installed tool (reference:
${CLAUDE_SKILL_DIR}/../reference/known-cli-dotdirs.md). Flag as "unknown — investigate".

### Step 5: Saved Application State

```bash
du -sh ~/Library/Saved\ Application\ State/ 2>/dev/null
```

Report size if over 10MB.

### Step 6: Crash Reports and Diagnostics

```bash
du -sh ~/Library/Logs/CrashReporter/ ~/Library/Logs/DiagnosticReports/ 2>/dev/null
```

Report size.

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

Present a table: plist label, load state (LOADED / NOT LOADED), target state
(OK / TARGET MISSING / UNKNOWN). Report only — do not offer removal.

Flag `homebrew.mxcl.*` agents whose formula is missing from `brew list --formula`
as "orphaned homebrew service".

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

Report sizes with notes on reclaimability.

## Phase 7: Docker

```bash
command -v docker >/dev/null 2>&1 && echo "OK" || echo "Phase 7 skipped — Docker not installed"
```
If skipped, skip this entire phase.

```bash
docker system df 2>/dev/null
```

Report usage breakdown. Note: if Docker not running, report size of
`~/Library/Containers/com.docker.docker/` and `~/.docker/` as reclaimable.

## Phase 8: Project Build Artifacts

Discover project directories:

```bash
for dir in ~/workspace ~/dev ~/Developer ~/code ~/src ~/projects ~/repos ~/Documents; do
  [ -d "$dir" ] && echo "FOUND: $dir"
done
```

```bash
find <DIRS> -maxdepth 4 -name "node_modules" -type d -exec du -sh {} + 2>/dev/null | sort -rh
find <DIRS> -maxdepth 4 \( -name ".venv" -o -name "venv" \) -type d -exec du -sh {} + 2>/dev/null | sort -rh
find <DIRS> -maxdepth 4 \( -name ".next" -o -name "dist" -o -name "build" -o -name "__pycache__" -o -name ".mypy_cache" -o -name ".pytest_cache" -o -name ".turbo" \) -type d -exec du -sh {} + 2>/dev/null | sort -rh | head -20
```

Report totals only.

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

1. **Dead PATH entries**: target directory doesn't exist
2. **Dead aliases**: target binary doesn't exist
3. **Dead sources**: sourced file doesn't exist
4. **Duplicate PATH entries**: duplicates in $PATH

Report all findings. No edits in audit mode.

## Phase 11: Electron App Caches

```bash
find ~/Library/Application\ Support -maxdepth 5 \( -name "Cache" -o -name "Code Cache" -o -name "Service Worker" -o -name "CachedData" -o -name "CachedExtension*" -o -name "PersistentCache" -o -name "GPUCache" \) -type d -exec du -sh {} + 2>/dev/null | sort -rh | head -15
```

Report caches over 50MB.

## Phase 12: Large File Scan

```bash
find ~/Downloads ~/Desktop -maxdepth 3 \( -name "*.dmg" -o -name "*.pkg" -o -name "*.iso" -o -name "*.zip" \) -not -path "*/.Trash/*" 2>/dev/null
```

Report with sizes.

## Phase 13: Trash

```bash
du -sh ~/.Trash/ 2>/dev/null
```

Report size.

## Phase 14: iPhone / iOS Backups

```bash
du -sh ~/Library/Application\ Support/MobileSync/Backup/ 2>/dev/null
ls -lht ~/Library/Application\ Support/MobileSync/Backup/ 2>/dev/null
```

Report total and per-backup sizes with dates.

## Phase 15: pipx Audit

```bash
command -v pipx >/dev/null 2>&1 && echo "OK" || echo "Phase 15 skipped — pipx not installed"
```
If skipped, skip this entire phase.

```bash
pipx list --short 2>/dev/null
```

List installed tools.

## Audit Report

Present the complete report:

```
## Audit Report

| # | Category | Reclaimable | Notes |
|---|----------|-------------|-------|
| 2 | Homebrew | ...MB | N packages outdated, N orphans |
| 3 | Dev caches | ...GB | |
| 4 | Orphaned app data | ...MB | N candidates |
| 5 | LaunchAgents | — | N with missing targets |
| 6 | Xcode & Dev Tools | ...GB | |
| 7 | Docker | ...GB | |
| 8 | Build artifacts | ...GB | |
| 9 | Stale logs | ...MB | |
| 10| Shell config | — | N dead entries |
| 11| Electron caches | ...MB | |
| 12| Large files | ...MB | |
| 13| Trash | ...GB | |
| 14| iOS backups | ...GB | N backups |
| 15| pipx tools | — | N tools installed |
| **Total reclaimable** | | **...GB** | |
```

End with: "Audit complete — nothing changed. Run `/upkeep:deepclean` to clean up."

## Rules

- NEVER remove, modify, or take any action — report only
- NEVER touch `~/Library/Application Support/Claude/` or `~/.claude/`
- Report Apple system directories only if they appear anomalously large
- Never execute sudo
