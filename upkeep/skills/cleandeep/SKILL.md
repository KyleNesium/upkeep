---
name: upkeep:cleandeep
version: 1.1.0-dev
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

# /upkeep:cleandeep — Full macOS Deep Clean

You are a macOS system cleanup specialist. Run all 15 phases. Report sizes,
ask before removing. Never run sudo.

## Environment Detection

Run this FIRST, before Phase 1. It sets `$OS_TYPE` (macos / linux / wsl2), `$OS_DISTRO` (ubuntu / debian / fedora / arch / macos / …), and `$PKG_MGR` (apt / dnf / pacman / unknown) — Phase 2/4/5/6/11/14 gate on `$OS_TYPE = "macos"`.

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

If `$OS_TYPE` is `unknown`, run Phase 1 (Baseline) only and skip every subsequent phase with the note "skipped (unsupported OS: $(uname -s))".

## Phase 1: Baseline

Record starting disk state for before/after comparison.

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

Capture "Available" and "Purgeable" from `diskutil info`. APFS volumes have
purgeable space that `df` doesn't distinguish — use `diskutil` for accurate
before/after. Fall back to `df` if unavailable.

> On Linux/WSL2, before/after comparison uses `df -h /` only — there is no APFS purgeable space to track.

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

If the nudge fires, display it once at the top before phase output.

## Phase 2: Homebrew Audit

```bash
if [ "$OS_TYPE" = "linux" ] || [ "$OS_TYPE" = "wsl2" ]; then
  echo "Phase 2: Linux package cache cleanup (pkg manager: $PKG_MGR)"
  case "$PKG_MGR" in
    apt)
      echo "--- Current apt cache size ---"
      du -sh /var/cache/apt/archives/ 2>/dev/null || echo "(unable to read — permission denied; continuing)"
      echo "--- apt-get clean (dry-run preview) ---"
      echo "Would run: apt-get clean  (removes /var/cache/apt/archives/*.deb)"
      echo "--- apt-get autoclean (dry-run preview) ---"
      apt-get autoclean --dry-run 2>/dev/null || echo "(dry-run unavailable; will only run with approval)"
      echo "--- apt autoremove (dry-run) ---"
      apt-get autoremove --dry-run 2>/dev/null | grep -E "^(Remv|The following)" || echo "No orphan packages to remove"
      echo "--- Old kernel images (superseded, reclaimable) ---"
      dpkg -l 'linux-image-*' 2>/dev/null | grep "^ii" | grep -v "$(uname -r)" | awk '{print $2}' || echo "No old kernel packages detected"
      ;;
    dnf)
      echo "--- Current dnf cache size ---"
      du -sh /var/cache/dnf/ 2>/dev/null || echo "(unable to read — permission denied; continuing)"
      echo "--- dnf clean all (preview) ---"
      echo "Would run: dnf clean all  (removes metadata + package cache)"
      echo "--- dnf autoremove (dry-run) ---"
      dnf autoremove --assumeno 2>/dev/null | grep -E "^(Remove|Removing)" || echo "No orphan packages to remove"
      ;;
    pacman)
      echo "--- Current pacman cache size ---"
      du -sh /var/cache/pacman/pkg/ 2>/dev/null || echo "(unable to read — permission denied; continuing)"
      echo "--- pacman cached packages (uninstalled only) ---"
      echo "Would run: pacman -Sc  (removes cached pkgs for uninstalled software, keeps installed versions)"
      echo "--- Orphan packages (pacman -Qtdq) ---"
      pacman -Qtdq 2>/dev/null || echo "No orphan packages to remove"
      ;;
    *)
      echo "Phase 2: skipped — unsupported package manager ($PKG_MGR)"
      # Stop this phase here. Continue to the next phase.
      ;;
  esac
  # End of Linux branch — DO NOT run the macOS brew commands below. Stop Phase 2 here, continue to Phase 3.
elif [ "$OS_TYPE" != "macos" ]; then
  echo "Phase 2: skipped (unsupported OS: $OS_TYPE)"
  # Stop this phase here. Continue to the next phase.
fi
```

**Approval gate.** Show the dry-run output verbatim. Ask: "Run the apt/dnf/pacman cache cleanup and autoremove shown above? (yes / no / skip-autoremove)". Execute only the parts the user approves:

> - `yes` → for apt: `apt-get clean && apt-get autoclean && apt-get autoremove -y`. For dnf: `dnf clean all && dnf autoremove -y`. For pacman: `pacman -Sc --noconfirm` then for each orphan printed by `pacman -Qtdq`, run `pacman -Rns --noconfirm <pkg>`.
> - `skip-autoremove` → run only the cache cleanup (apt-get clean / dnf clean all / pacman -Sc --noconfirm). Do NOT remove orphans.
> - `no` → skip Phase 2 entirely, continue to Phase 3.
>
> Never use sudo. If any command fails with a permission error, surface the sudo'd command to the user in a fenced bash block under ## Manual Steps and move on.

If the Linux branch ran above, stop this phase and move to the next. Do not execute any subsequent `mdfind`/`defaults`/`launchctl`/`xcode-select` commands below.

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
5. `brew leaves` — top-level packages. Present the list and prompt:
   "Uninstall any of these? (space-separated names, or 'none')"
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

### Step 3: Linux user cache approval (Linux/WSL2 only)

```bash
if [ "$OS_TYPE" = "linux" ] || [ "$OS_TYPE" = "wsl2" ]; then
  echo "=== Total ~/.cache size ==="
  du -sh ~/.cache/ 2>/dev/null || echo "~/.cache/ not present"
  echo "=== Top 15 subdirectories (sorted largest first) ==="
  du -sh ~/.cache/*/ 2>/dev/null | sort -rh | head -15
fi
```

> **Linux cache removal — approval gate.** If the output above shows any subdirectory over 100MB, present it as a numbered table (index, path, size) and prompt: "Remove which? (space-separated indices, 'all', or 'none')". For each approved index, run `rm -rf ~/.cache/<subdir>/`. NEVER clear `~/.cache/` as a whole directory — some tools (e.g. `~/.cache/mesa_shader_cache`, `~/.cache/fontconfig`) rebuild slowly and impact desktop startup. Only remove named subdirectories the user approves. Known-safe-to-remove subdirs: `pip`, `yarn`, `pnpm`, `go-build`, `thumbnails`, `mozilla`, `chromium`, `vscode-cpptools`. Known-costly-to-rebuild (warn before removing): `mesa_shader_cache`, `fontconfig`, `nvidia`.

## Phase 4: Orphaned Application Data

```bash
if [ "$OS_TYPE" != "macos" ]; then
  echo "Phase 4: skipped (macOS only) — detected $OS_TYPE"
  # Stop this phase here. Continue to the next phase.
fi
```

If the guard prints the skip line, stop this phase and move to the next. Do not execute any subsequent `mdfind`/`defaults`/`launchctl`/`xcode-select` commands below.

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
Cross-reference ${CLAUDE_SKILL_DIR}/../upkeep/reference/known-cli-dotdirs.md.

### Step 2: Scan Application Support

```bash
ls ~/Library/Application\ Support/ 2>/dev/null
```

For each directory:
- Skip any matching ${CLAUDE_SKILL_DIR}/../upkeep/reference/apple-system-dirs.md
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
Read ${CLAUDE_SKILL_DIR}/../upkeep/reference/known-cli-dotdirs.md.
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

Present a table: plist label, load state, target state. Then:
"Remove which? (comma-separated indices, or 'none')" — per-agent confirmation required.

**Exclusions:**
- `homebrew.mxcl.*`: managed by `brew services`. Never offer removal. Orphaned
  ones (formula absent from brew list) appear in the table as "ORPHANED HOMEBREW
  SERVICE" — tell the user to run `brew services cleanup`.
- Agents matching user's reverse-DNS domain: flag as "user-owned".

To remove:
```bash
launchctl bootout gui/$(id -u)/<label> 2>/dev/null || \
  launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/<plist>
rm -f ~/Library/LaunchAgents/<plist>
```

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

| Item | Safe to clear? | Notes |
|------|----------------|-------|
| DerivedData | Yes | Rebuild cache. Always safe. |
| Archives | Ask user | Old app archives. May want to keep recent ones. |
| iOS DeviceSupport | Mostly | Old device symbols. Keep ones matching current devices. |
| CoreSimulator | Partially | Preview count before offering removal (see note below). |

For CoreSimulator: first run `xcrun simctl list devices 2>/dev/null | grep -c Shutdown` to show how many shutdown simulators exist, then offer `xcrun simctl delete unavailable`.

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
find <DIRS> -maxdepth 4 \( -name ".next" -o -name "dist" -o -name "build" -o -name "out" -o -name "target" -o -name "__pycache__" -o -name ".mypy_cache" -o -name ".pytest_cache" -o -name ".turbo" -o -name ".nx" -o -name "Pods" -o -name ".build" -o -name "coverage" \) -type d -exec du -sh {} + 2>/dev/null | sort -rh | head -20
```

Report totals. Offer to remove with user approval — all are rebuildable via
`npm install` / `pip install` etc.

## Phase 9: Stale Logs

```bash
if [ "$OS_TYPE" = "linux" ] || [ "$OS_TYPE" = "wsl2" ]; then
  echo "=== systemd journal disk usage ==="
  journalctl --disk-usage 2>/dev/null || echo "journalctl not available"
  echo "=== user journal (no sudo) ==="
  journalctl --user --disk-usage 2>/dev/null || echo "user journal not configured"
fi
```

> **Journal vacuum — approval gate (Linux/WSL2 only).** If `journalctl --disk-usage` reports more than 500MB, prompt: "Vacuum the user journal to 200MB? (yes / no)". On yes, run:
>
> ```bash
> journalctl --user --vacuum-size=200M 2>/dev/null || echo "user journal vacuum unavailable"
> ```
>
> The system journal requires sudo — never execute it. If the system journal disk usage is over 500MB, surface this exact command under ## Manual Steps:
>
> ```bash
> # Vacuum system journal to 500MB (requires sudo)
> sudo journalctl --vacuum-size=500M
> ```
>
> After the Linux journal block, fall through to the macOS log scans below only when `$OS_TYPE = "macos"`. On Linux/WSL2 the existing `~/Library/Logs` scans will naturally return empty and can run — but to avoid noise, wrap the rest of Phase 9 in an `if [ "$OS_TYPE" = "macos" ]; then ... fi` guard.

```bash
if [ "$OS_TYPE" = "macos" ]; then
  ls ~/Library/Logs/ 2>/dev/null
fi
```

Cross-reference against installed apps. Flag:
1. Log directories from uninstalled apps
2. Rotated log files — scan for them:
```bash
if [ "$OS_TYPE" = "macos" ]; then
  find ~/Library/Logs -maxdepth 3 \( -name "*.old" -o -name "*.old.*" -o -name "*.log.old" -o -name "*.log.[0-9]*" \) \
    -exec du -sh {} + 2>/dev/null | sort -rh
fi
```
3. Any single log file over 10MB:
```bash
if [ "$OS_TYPE" = "macos" ]; then
  find ~/Library/Logs -maxdepth 3 -name "*.log" -size +10M \
    -exec du -sh {} + 2>/dev/null | sort -rh
fi
```

## Phase 10: Shell Config Audit

Read `~/.zshrc`, `~/.zprofile`, `~/.zshenv`, `~/.bash_profile` (whichever exist):

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

Only show caches over 50MB. Before offering to clear, check if app is running:
`pgrep -x "<AppName>" >/dev/null 2>&1`
If running: "Electron cache skipped — <AppName> is running". Do NOT use `pgrep -f`.
Only offer clearing for confirmed-not-running apps.

## Phase 12: Large File Scan

```bash
find ~/Downloads ~/Desktop -maxdepth 3 \( -name "*.dmg" -o -name "*.pkg" -o -name "*.iso" -o -name "*.zip" \) -not -path "*/.Trash/*" -exec du -sh {} + 2>/dev/null | sort -rh
```

Report with sizes. Offer to remove.

## Phase 13: Trash

```bash
du -sh ~/.Trash/ 2>/dev/null
```

Offer: `rm -rf ~/.Trash/*` or suggest Finder (Cmd+Shift+Delete).

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

## Phase 16: Snap & Flatpak Cleanup (Linux/WSL2)

```bash
if [ "$OS_TYPE" != "linux" ] && [ "$OS_TYPE" != "wsl2" ]; then
  echo "Phase 16: skipped (Linux/WSL2 only) — detected $OS_TYPE"
  # Stop this phase here. Continue to Reporting.
fi
```

If the guard prints the skip line, stop this phase and move to Reporting. Do not execute any of the snap/flatpak commands below.

### Step 1: Snap

```bash
if command -v snap >/dev/null 2>&1; then
  echo "=== Snap installed packages ==="
  snap list 2>/dev/null | tail -n +2 | wc -l
  echo "=== Snap total disk usage ==="
  du -sh /var/lib/snapd/snaps/ 2>/dev/null || echo "(unable to read)"
  echo "=== Snap disabled revisions (reclaimable) ==="
  snap list --all 2>/dev/null | awk '/disabled/ {print $1, $3}'
else
  echo "Phase 16 Step 1: snap not installed — skipping"
fi
```

**Approval gate (Snap).** If `snap list --all` prints any disabled revisions, show them as a numbered table (index, package name, revision number). Prompt: "Remove which disabled revisions? (space-separated indices, 'all', or 'none')". For each approved `<pkg> <rev>` pair, run:

```bash
snap remove --revision=<rev> <pkg>
```

Never use sudo with snap commands — modern snapd policy allows user removal of disabled revisions on most distros. If snap refuses with a permission error, surface the sudo'd command under ## Manual Steps and move on:

```bash
# Remove snap disabled revision (if user space fails)
sudo snap remove --revision=<rev> <pkg>
```

### Step 2: Flatpak

```bash
if command -v flatpak >/dev/null 2>&1; then
  echo "=== Flatpak installed apps ==="
  flatpak list --app 2>/dev/null | wc -l
  echo "=== Flatpak installed runtimes ==="
  flatpak list --runtime 2>/dev/null | wc -l
  echo "=== Flatpak total disk usage ==="
  du -sh ~/.local/share/flatpak/ /var/lib/flatpak/ 2>/dev/null || echo "(paths unavailable)"
  echo "=== Installed runtimes (each may or may not be unused) ==="
  flatpak list --runtime --columns=application,branch,size 2>/dev/null
else
  echo "Phase 16 Step 2: flatpak not installed — skipping"
fi
```

**Approval gate (Flatpak).** If `flatpak list --runtime` shows any runtimes, prompt: "Remove unused flatpak runtimes? (yes / no)". On `yes`, run:

```bash
flatpak uninstall --unused --assumeyes
```

This removes only runtimes that no installed app depends on — safe by definition. If the user says `no`, skip to Reporting.

Never use sudo — flatpak operates on the user's install by default. For system-wide flatpak installs, surface the sudo command under ## Manual Steps:

```bash
# Remove unused system-wide flatpak runtimes
sudo flatpak uninstall --unused --assumeyes --system
```

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
