---
name: upkeep:audit
version: 1.1.0-dev
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
  - Bash(touch *)
  - Bash(id *)
  - Bash(basename *)
  - Bash(command *)
  - Bash(which *)
  - Bash(pgrep *)
  - Bash(mdfind *)
  - Bash(mdutil *)
  - Bash(defaults *)
  - Bash(/usr/libexec/PlistBuddy *)
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

# /upkeep:audit — Full macOS Disk Audit

You are a macOS system auditor. Run all 15 phases. **Report findings and sizes
only — never offer to remove, clean, modify, or take any action.** This is a
read-only scan. The goal is a complete picture of what's reclaimable.

## Environment Detection

Run this FIRST, before Phase 1. It sets `$OS_TYPE` (macos / linux / wsl2), `$OS_DISTRO`, and `$PKG_MGR` — Phases 2, 4, 5, 6, 11, 14 gate on `$OS_TYPE = "macos"`.

```bash
# ── OS Detection (run once, export for all phases) ────────────────
_KERNEL=$(uname -s 2>/dev/null || echo "unknown")
_KREL=$(uname -r 2>/dev/null || echo "")
case "$_KERNEL" in
  Darwin)
    OS_TYPE="macos"
    OS_DISTRO="macos"
    ;;
  Linux)
    if echo "$_KREL" | grep -qi "microsoft"; then
      OS_TYPE="wsl2"
    else
      OS_TYPE="linux"
    fi
    if [ -r /etc/os-release ]; then
      OS_DISTRO=$(. /etc/os-release 2>/dev/null; echo "${ID_LIKE:-$ID}" | awk '{print $1}')
    elif command -v lsb_release >/dev/null 2>&1; then
      OS_DISTRO=$(lsb_release -si 2>/dev/null | tr '[:upper:]' '[:lower:]')
    else
      OS_DISTRO="unknown"
    fi
    case "$OS_DISTRO" in
      debian|ubuntu) PKG_MGR="apt" ;;
      fedora|rhel|centos|rocky|almalinux) PKG_MGR="dnf" ;;
      arch|manjaro|endeavouros) PKG_MGR="pacman" ;;
      *) PKG_MGR="unknown" ;;
    esac
    ;;
  *)
    OS_TYPE="unknown"
    OS_DISTRO="unknown"
    PKG_MGR="unknown"
    ;;
esac
export OS_TYPE OS_DISTRO PKG_MGR
echo "Environment: $OS_TYPE / $OS_DISTRO${PKG_MGR:+ (pkg: $PKG_MGR)}"
```

If `$OS_TYPE` is `unknown`, run Phase 1 Baseline only and skip remaining phases with the note "skipped (unsupported OS: $(uname -s))".

## Phase 1: Baseline

```bash
if [ "$OS_TYPE" = "macos" ]; then
  echo "=== Disk ===" && diskutil info / 2>/dev/null | grep -E "Free|Available|Purgeable" || df -h / | tail -1
  echo "=== macOS ===" && sw_vers
  echo "=== Homebrew ===" && brew --version 2>/dev/null || echo "not installed"
elif [ "$OS_TYPE" = "linux" ] || [ "$OS_TYPE" = "wsl2" ]; then
  echo "=== Disk ===" && df -h / | tail -1
  echo "=== OS ===" && (cat /etc/os-release 2>/dev/null | grep -E "^(NAME|VERSION|ID)=" || echo "unknown")
  echo "=== Kernel ===" && uname -r
  echo "=== Package Manager ===" && echo "Detected: $PKG_MGR"
  case "$PKG_MGR" in
    apt)    apt-cache stats 2>/dev/null | head -3 || echo "apt-cache not available" ;;
    dnf)    dnf --version 2>/dev/null | head -1 || echo "dnf not available" ;;
    pacman) pacman --version 2>/dev/null | head -1 || echo "pacman not available" ;;
    *) echo "No supported package manager detected" ;;
  esac
fi
```

Capture "Available" and "Purgeable" from `diskutil info`.

On Linux/WSL2, the baseline uses `df -h /` only — there is no APFS purgeable space.

Then run a passive update check (at most once per 24h, silent on all failures):

```bash
if [ "${UPKEEP_SKIP_UPDATE_CHECK:-}" != "1" ] && command -v git >/dev/null 2>&1; then
  _CHECK_FILE="${CLAUDE_SKILL_DIR}/../../../.last-update-check"
  _LAST=$(stat -f %m "$_CHECK_FILE" 2>/dev/null || stat -c %Y "$_CHECK_FILE" 2>/dev/null || echo 0)
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
if [ "$OS_TYPE" = "linux" ] || [ "$OS_TYPE" = "wsl2" ]; then
  echo "Phase 2: Linux package state (read-only — pkg: $PKG_MGR)"
  case "$PKG_MGR" in
    apt)
      echo "=== Installed packages (count) ==="
      dpkg -l 2>/dev/null | grep -c '^ii' || echo "dpkg not available"
      echo "=== apt cache size ==="
      du -sh /var/cache/apt/archives/ 2>/dev/null || echo "(unable to read)"
      echo "=== Orphan packages (autoremove preview) ==="
      apt-get autoremove --dry-run 2>/dev/null | grep -E "^(Remv|The following)" | head -20 || echo "none"
      ;;
    dnf)
      echo "=== Installed packages (count) ==="
      dnf list installed 2>/dev/null | wc -l
      echo "=== dnf cache size ==="
      du -sh /var/cache/dnf/ 2>/dev/null || echo "(unable to read)"
      echo "=== Orphan packages (autoremove preview) ==="
      dnf autoremove --assumeno 2>/dev/null | grep -E "^(Remove|Removing)" | head -20 || echo "none"
      ;;
    pacman)
      echo "=== Installed packages (count) ==="
      pacman -Q 2>/dev/null | wc -l
      echo "=== pacman cache size ==="
      du -sh /var/cache/pacman/pkg/ 2>/dev/null || echo "(unable to read)"
      echo "=== Orphan packages (pacman -Qtdq) ==="
      pacman -Qtdq 2>/dev/null || echo "none"
      ;;
    *)
      echo "Phase 2: no supported package manager detected"
      ;;
  esac
  # End of Linux branch — stop Phase 2, continue to Phase 3. Do NOT run brew commands below.
elif [ "$OS_TYPE" != "macos" ]; then
  echo "Phase 2: skipped (unsupported OS: $OS_TYPE)"
  # Stop this phase here. Continue to the next phase.
fi
```

If the guard prints the skip line, stop this phase and move to the next. Do not execute any subsequent `mdfind`/`defaults`/`launchctl`/`xcode-select` commands below.

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

Read the cache table from ${CLAUDE_SKILL_DIR}/../upkeep/reference/dev-tool-caches.md.
Check each listed location. Report size. Skip any that don't exist.

### Step 2: Discovery scan

```bash
du -sh ~/.cache/*/ 2>/dev/null | sort -rh | head -15
du -sh ~/Library/Caches/*/ 2>/dev/null | sort -rh | head -15
```

Report anything over 50MB not in the known list.

## Phase 4: Orphaned Application Data

```bash
if [ "$OS_TYPE" != "macos" ]; then
  echo "Phase 4: skipped (macOS only) — detected $OS_TYPE"
  # Stop this phase here. Continue to the next phase.
fi
```

If the guard prints the skip line, stop this phase and move to the next. Do not execute any subsequent `mdfind`/`defaults`/`launchctl`/`xcode-select` commands below.

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

Cross-reference ${CLAUDE_SKILL_DIR}/../upkeep/reference/known-cli-dotdirs.md for CLI tools.

### Step 2: Scan Application Support

```bash
ls ~/Library/Application\ Support/ 2>/dev/null
```

Skip entries matching ${CLAUDE_SKILL_DIR}/../upkeep/reference/apple-system-dirs.md.
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
${CLAUDE_SKILL_DIR}/../upkeep/reference/known-cli-dotdirs.md). Flag as "unknown — investigate".

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
if [ "$OS_TYPE" != "macos" ]; then
  echo "Phase 5: skipped (macOS only) — detected $OS_TYPE"
  # Stop this phase here. Continue to the next phase.
fi
```

If the guard prints the skip line, stop this phase and move to the next. Do not execute any subsequent `mdfind`/`defaults`/`launchctl`/`xcode-select` commands below.

```bash
_BREW_FORMULA=$(brew list --formula 2>/dev/null)
for plist in ~/Library/LaunchAgents/*.plist; do
  [ -f "$plist" ] || continue
  label=$(basename "$plist" .plist)
  if [[ "$label" == homebrew.mxcl.* ]]; then
    _formula="${label#homebrew.mxcl.}"
    echo "$_BREW_FORMULA" | grep -qx "$_formula" || \
      echo "$label | NOT LOADED | ORPHANED HOMEBREW SERVICE"
    continue
  fi
  target=$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Print :Program" "$plist" 2>/dev/null || echo "UNKNOWN")
  launchctl list 2>/dev/null | grep -q "$label" && load="LOADED" || load="NOT LOADED"
  [ "$target" = "UNKNOWN" ] && tgt="UNKNOWN" || { [ -e "$target" ] && tgt="OK" || tgt="TARGET MISSING"; }
  echo "$label | $load | $tgt"
done
```

Present a table: plist label, load state (LOADED / NOT LOADED), target state
(OK / TARGET MISSING / UNKNOWN / ORPHANED HOMEBREW SERVICE). Report only — do not offer removal.

## Phase 6: Xcode & Developer Tools

```bash
if [ "$OS_TYPE" != "macos" ]; then
  echo "Phase 6: skipped (macOS only) — detected $OS_TYPE"
  # Stop this phase here. Continue to the next phase.
fi
```

If the guard prints the skip line, stop this phase and move to the next. Do not execute any subsequent `mdfind`/`defaults`/`launchctl`/`xcode-select` commands below.

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

| Item | Reclaimable? | Notes |
|------|-------------|-------|
| DerivedData | Yes | Rebuild cache — always safe to clear. |
| Archives | Partially | Old app archives. Recent ones may be needed. |
| iOS DeviceSupport | Mostly | Device debug symbols. Keep ones matching current devices. |
| CoreSimulator | Partially | Count stale simulators (see note below). |

For CoreSimulator: run `xcrun simctl list devices 2>/dev/null | grep -c Shutdown` and report how many shutdown simulators exist.

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
find <DIRS> -maxdepth 4 \( -name ".next" -o -name "dist" -o -name "build" -o -name "out" -o -name "target" -o -name "__pycache__" -o -name ".mypy_cache" -o -name ".pytest_cache" -o -name ".turbo" -o -name ".nx" -o -name "Pods" -o -name ".build" -o -name "coverage" \) -type d -exec du -sh {} + 2>/dev/null | sort -rh | head -20
```

Report totals only.

## Phase 9: Stale Logs

```bash
ls ~/Library/Logs/ 2>/dev/null
```

Cross-reference against installed apps. Flag:
1. Log directories from uninstalled apps
2. Rotated log files — scan for them:
```bash
find ~/Library/Logs -maxdepth 3 \( -name "*.old" -o -name "*.old.*" -o -name "*.log.old" -o -name "*.log.[0-9]*" \) \
  -exec du -sh {} + 2>/dev/null | sort -rh
```
3. Any single log file over 10MB:
```bash
find ~/Library/Logs -maxdepth 3 -name "*.log" -size +10M \
  -exec du -sh {} + 2>/dev/null | sort -rh
```

## Phase 10: Shell Config Audit

Read `~/.zshrc`, `~/.zprofile`, `~/.zshenv`, `~/.bash_profile` (whichever exist):

1. **Dead PATH entries**: target directory doesn't exist
2. **Dead aliases**: target binary doesn't exist
3. **Dead sources**: sourced file doesn't exist
4. **Duplicate PATH entries**: duplicates in $PATH

**Conditional blocks are report-only.** Lines inside `if`/`fi`, `case`/`esac`,
or containing `&& `/`|| ` operators are never flagged as safe-to-remove — report
as findings only. These gate on env/hostname/OS.

Report all findings. No edits in audit mode.

## Phase 11: Electron App Caches

```bash
if [ "$OS_TYPE" != "macos" ]; then
  echo "Phase 11: skipped (macOS only) — detected $OS_TYPE"
  # Stop this phase here. Continue to the next phase.
fi
```

If the guard prints the skip line, stop this phase and move to the next. Do not execute any subsequent `mdfind`/`defaults`/`launchctl`/`xcode-select` commands below.

```bash
find ~/Library/Application\ Support -maxdepth 5 \
  -not -path "*/Claude/*" -not -path "*/Claude" \
  \( -name "Cache" -o -name "Code Cache" -o -name "Service Worker" -o -name "CachedData" -o -name "CachedExtension*" -o -name "PersistentCache" -o -name "GPUCache" \) \
  -type d -exec du -sh {} + 2>/dev/null | sort -rh | head -15
```

Report caches over 50MB.

## Phase 12: Large File Scan

```bash
find ~/Downloads ~/Desktop -maxdepth 3 \( -name "*.dmg" -o -name "*.pkg" -o -name "*.iso" -o -name "*.zip" \) -not -path "*/.Trash/*" -exec du -sh {} + 2>/dev/null | sort -rh
```

Report with sizes.

## Phase 13: Trash

```bash
du -sh ~/.Trash/ 2>/dev/null
```

Report size.

## Phase 14: iPhone / iOS Backups

```bash
if [ "$OS_TYPE" != "macos" ]; then
  echo "Phase 14: skipped (macOS only) — detected $OS_TYPE"
  # Stop this phase here. Continue to the next phase.
fi
```

If the guard prints the skip line, stop this phase and move to the next. Do not execute any subsequent `mdfind`/`defaults`/`launchctl`/`xcode-select` commands below.

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

End with: "Audit complete — nothing changed. Run `/upkeep:cleandeep` to clean up."

## Rules

- NEVER remove, modify, or take any action — report only
- NEVER touch `~/Library/Application Support/Claude/` or `~/.claude/`
- NEVER report Apple system directories (`com.apple.*`) as orphan candidates — skip them
- NEVER report `~/Library/Keychains/` or `~/Library/Preferences/` contents
- Report Apple system directories only if they appear anomalously large (>1GB)
- Shell config audit: flag dead entries as findings only, never suggest edits
- Conditional blocks (`if`/`fi`, `&& `/ `|| `) are findings only — do not suggest removal
- Never execute sudo
