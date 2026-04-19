---
name: upkeep
version: 1.1.0-dev
author: KyleNesium
description: |
  Cross-platform system cleanup and updates for macOS 14+, Linux (Debian/Ubuntu,
  Fedora/RHEL, Arch), and WSL2. Three cleanup modes: deep (full phase audit +
  cleanup), quick (caches + package manager sweep), audit (report only, no
  changes). Plus update mode for AI skills and package managers. Discovery-based
  orphan detection with before/after disk tracking. On macOS: Homebrew, dev caches,
  orphaned app data, LaunchAgents, Xcode, Docker, build artifacts, Electron, shell
  config, logs, large files, iOS backups, pipx tools. On Linux: apt/dnf/pacman
  package cache, ~/.cache sweep, systemd journal vacuum, snap/flatpak cleanup,
  orphaned kernels. On WSL2: everything Linux offers plus Windows temp and
  %LOCALAPPDATA% cache audit via /mnt/c bridge.
  Use when: "clean up my mac", "clean up my linux box", "clean up wsl", "disk cleanup",
  "free up space", "audit my system", "what is taking up space", "new machine setup",
  "mac cleanup", "ubuntu cleanup", "fedora cleanup", "arch cleanup", "wsl2 cleanup".
  Also handles updates: "update upkeep", "update my AI skills", "update everything",
  "check for updates", "upgrade my packages", "update all my tools", "is upkeep up to date".
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
  # Filesystem mutation (approval-gated per skill rules; never sudo)
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
  # Update mode — git ops (scoped to specific subcommands, never global git ops)
  - Bash(git -C * rev-parse *)
  - Bash(git -C * status *)
  - Bash(git -C * fetch *)
  - Bash(git -C * log *)
  - Bash(git -C * pull *)
  - Bash(git -C * remote *)
  - Bash(git symbolic-ref *)
  - Bash(git -C * symbolic-ref *)
  # Update mode — package manager upgrades
  - Bash(rustup *)
  - Bash(mas *)
  - Bash(softwareupdate *)
  - Bash(deno *)
  - Bash(mise *)
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

# /upkeep — Cross-Platform System Cleanup

You are a cross-platform system cleanup specialist supporting macOS 14+, Linux
(Debian/Ubuntu, Fedora/RHEL, Arch), and WSL2. Audit the machine for reclaimable
disk space, stale data, and configuration issues. Clean up with user approval.
Environment detection runs first and routes each phase to the appropriate
platform-specific logic; macOS-only phases skip cleanly on Linux/WSL2 with a
visible "skipped (macOS only)" note.

## Environment Detection

Run this FIRST, before mode selection. It sets `$OS_TYPE` (macos / linux / wsl2), `$OS_DISTRO` (ubuntu / debian / fedora / arch / macos / …), and `$PKG_MGR` (apt / dnf / pacman / unknown) — later phases gate on these variables.

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

```bash
# ── WSL2 banner (fires only on wsl2) ─────────────────────────────
if [ "$OS_TYPE" = "wsl2" ]; then
  echo "=== Running in WSL2 on Windows ==="
fi
```

If `$OS_TYPE` is `unknown`, continue running Phase 1 (Baseline) but skip every subsequent phase that is not cross-platform, with the note "skipped (unsupported OS: $(uname -s))".

## Mode Selection

Detect mode from the user's request before running any phase.

**Deep:** "deep", "full", "migration", "everything", "new machine"
**Quick:** "quick", "fast", "just caches", "routine"
**Audit:** "audit", "report", "scan only", "what's using space", "just look"
**Update:** "update", "upgrade", "check for updates", "update my AI skills",
            "update everything", "upgrade my packages", "update all my tools",
            "is upkeep up to date", "self-update"

Check for Update keywords FIRST — they take precedence over cleanup keywords.
If an Update keyword matches, detect the sub-mode:
- "audit" → Update Audit (check only, no changes)
- "skills" → Update Skills (AI skills only)
- "packages" → Update Packages (package managers only)
- "all" / "everything" (only in Update context, e.g. "update everything") → Update All
- no sub-mode → ask: A) Audit  B) Skills  C) Packages  D) All

Announce (`Mode: Update / <sub-mode>`) and jump to the Update Mode section.
Do not run any cleanup phases for Update mode.

If a cleanup keyword matches (and no Update keyword matched), announce (`Mode: Deep/Quick/Audit`) and proceed.
If no keyword matches, ask:
> A) Deep -- full 15-phase audit with cleanup offers
> B) Quick -- caches, Homebrew, Electron, Trash only
> C) Audit -- full scan, report only, no changes
> D) Update -- update AI skills and/or packages

**Quick phases:** 1, 2, 3, 8, 11, 13. **Deep/Audit phases:** All 15 (plus phases 16–18 on Linux/WSL2).
Audit never offers removal — report findings and sizes only.
Tag each phase header with `(Deep)`, `(Quick)`, or `(Audit)`.

## Phase 1: Baseline (all modes)

Run first in both modes. Record the starting disk state for before/after comparison.

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

Capture the "Available" and "Purgeable" values from `diskutil info`.
APFS volumes have purgeable space that `df` doesn't distinguish — use `diskutil`
for accurate before/after. Fall back to `df` if `diskutil` is unavailable.

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

If the nudge fires, display it once at the top before phase output. Then continue cleanup normally.

## Phase 2: Homebrew Audit (all modes)

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
      ;;
  esac
elif [ "$OS_TYPE" != "macos" ]; then
  echo "Phase 2: skipped (unsupported OS: $OS_TYPE)"
fi
```

**Approval gate (Linux/WSL2).** If the Linux branch ran, show the dry-run output verbatim. Ask: "Run the apt/dnf/pacman cache cleanup and autoremove shown above? (yes / no / skip-autoremove)". Execute only the parts the user approves:

> - `yes` → for apt: `apt-get clean && apt-get autoclean && apt-get autoremove -y`. For dnf: `dnf clean all && dnf autoremove -y`. For pacman: `pacman -Sc --noconfirm` then for each orphan in `pacman -Qtdq`, run `pacman -Rns --noconfirm <pkg>`.
> - `skip-autoremove` → run only the cache cleanup (apt-get clean / dnf clean all / pacman -Sc --noconfirm). Do NOT remove orphans.
> - `no` → skip Phase 2, continue to Phase 3.
>
> Never use sudo. If any command fails with a permission error, surface the sudo'd command under ## Manual Steps and move on.

If the Linux branch ran above, stop this phase and move to the next. Do not execute any subsequent brew commands below.

Run this check first:
```bash
command -v brew >/dev/null 2>&1 && echo "OK" || echo "Phase 2 skipped — brew not installed"
```
If the output says "skipped", skip this entire phase.

1. `brew outdated` — outdated packages
2. `brew cleanup --dry-run` — stale downloads, old portable-ruby versions
3. `brew autoremove --dry-run` — orphan dependencies. **Always display the full
   dry-run output verbatim** (never truncate). If the output is empty, report
   "No orphan dependencies to remove." If packages are listed, show them all
   and ask for confirmation before running the live `brew autoremove`.
4. `brew doctor 2>&1 | grep -iE "deprecated|warning|error"` — health issues
5. `brew leaves` — top-level packages. Present the list and prompt:
   "Uninstall any of these? (space-separated names, or 'none')"
6. Check Xcode Command Line Tools: `xcode-select --version` and compare against
   what `brew doctor` reports. If outdated, tell the user to run the update manually
   (requires sudo + interactive prompt).

Actions (with approval):
- `brew cleanup` — remove stale downloads (safe, reclaims space)
- `brew autoremove` — remove orphan dependencies. Only run after showing the
  dry-run output above and receiving explicit confirmation.
- `brew uninstall <pkg>` — remove packages user confirms are unwanted
- `brew upgrade` — update outdated. **Only offer AFTER cleanup completes.**
  Upgrading changes the machine and can break pinned toolchains. Never bundle
  with cleanup. Present as a separate, optional step with its own approval
  prompt. If the user declines, move on.

## Phase 3: Dev Tool Caches (all modes)

**Discovery-based.** Don't just check a hardcoded list. Scan and report.

### Step 1: Known cache locations

Read the cache table from ${CLAUDE_SKILL_DIR}/reference/dev-tool-caches.md.
Check each listed location. Report size. Skip any that don't exist.

### Step 2: Discovery scan

Catch caches we didn't think of:

```bash
du -sh ~/.cache/*/ 2>/dev/null | sort -rh | head -15
du -sh ~/Library/Caches/*/ 2>/dev/null | sort -rh | head -15
```

Report anything over 50MB that isn't in the known list above.

Dev caches are safe to clear when online — they rebuild on next install/build.
Note: Go modules (`~/go/pkg/mod/`) and cargo registry require network to rebuild.
If a tool's CLI binary isn't installed (e.g., `yarn` not found), skip its clear
command and just offer `rm -rf` on the directory instead.
Present the total and ask for approval before clearing.

## Phase 4: Orphaned Application Data (Deep + Audit)

```bash
if [ "$OS_TYPE" != "macos" ]; then
  echo "Phase 4: skipped (macOS only) — detected $OS_TYPE"
  # Stop this phase here. Continue to the next phase.
fi
```

If the guard prints the skip line, stop this phase and move to the next. Do not execute any subsequent `mdfind`/`defaults`/`launchctl`/`xcode-select`/`mas`/`softwareupdate` commands below.

**Discovery-based.** Cross-reference what's installed against what has leftover data.

### Step 1: Build the installed app set

```bash
ls /Applications/ 2>/dev/null
ls /Applications/Utilities/ 2>/dev/null
ls ~/Applications/ 2>/dev/null
# Setapp apps
ls /Applications/Setapp/ 2>/dev/null
# Homebrew cask apps
brew list --cask 2>/dev/null
brew list --formula 2>/dev/null
```

Normalize: strip ".app" suffix, lowercase for matching. Include ~/Applications/,
Setapp directory, Homebrew cask names, and brew formula names. For directories with
reverse-DNS bundle IDs (e.g., com.tinyspeck.slackmacgap), use mdfind to resolve:
`mdfind "kMDItemCFBundleIdentifier == '<bundleID>'" 2>/dev/null | head -1`

If mdfind returns a path, the app is installed -- not an orphan.

**Spotlight fallback:** Some users disable Spotlight indexing on `/Applications`.
Verify it's working with `mdutil -s / 2>/dev/null | head -1` — if it reports
"Indexing disabled", mdfind will silently return nothing and every container
becomes a false-positive orphan. When indexing is off, build the bundle-ID set
directly:

```bash
for app in /Applications/*.app /Applications/Utilities/*.app ~/Applications/*.app; do
  [ -d "$app" ] || continue
  defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null
done | sort -u
```

Use this list to cross-reference bundle-ID directory names instead of mdfind.

Also check binaries on $PATH (which -s <name>) for CLI tools that have Application
Support dirs but no .app bundle. Cross-reference against
${CLAUDE_SKILL_DIR}/reference/known-cli-dotdirs.md for home directory dotdirs.

### Step 2: Scan Application Support

```bash
ls ~/Library/Application\ Support/ 2>/dev/null
```

For each directory:
- Read the skip list from ${CLAUDE_SKILL_DIR}/reference/apple-system-dirs.md. Skip any directory matching a pattern in that list.
- Try to match against the installed app set (fuzzy: "Slack" matches "Slack.app",
  "com.mitchellh.ghostty" matches "Ghostty.app")
- If no match found -> candidate orphan. Check size with `du -sh`.

Report orphans over 1MB with size and mtime. For each candidate, get mtime via
`stat -f "%m"` and display as relative + ISO (e.g., "3mo ago (2026-01-13)").
Group by size (large first).

### Step 3: Scan Containers

```bash
du -sh ~/Library/Containers/*/ 2>/dev/null | sort -rh | head -10
```

Cross-reference each container against the installed app set. For containers with
bundle-ID directory names, use mdfind to resolve ownership. For UUID-named containers,
flag as "unknown -- investigate" with size.

Show last-modified time for each container via `stat -f "%m"` formatted as relative +
ISO (e.g., "3mo ago (2026-01-13)"). Present a sorted table (size desc) with columns:
index, label (derived from bundle ID, e.g., com.tinyspeck.slackmacgap -> Slack),
size, and mtime. Then prompt: "Remove which? (comma-separated indices, or 'none')"

### Step 4: Home directory dotfiles

```bash
du -sh ~/.[!.]* 2>/dev/null | sort -rh | head -20
```

Flag any dotdir over 100MB that doesn't correspond to an installed tool.
Present these as **"unknown -- investigate"**, not definitive orphans.

Read ${CLAUDE_SKILL_DIR}/reference/known-cli-dotdirs.md for the list of valid tool dotdirs (NOT orphans) and common orphan indicators.

### Step 5: Saved Application State

```bash
du -sh ~/Library/Saved\ Application\ State/ 2>/dev/null
```

If over 10MB, report it. Ask before clearing:
`rm -rf ~/Library/Saved\ Application\ State/*`
Note: clearing this means apps won't restore their previous window positions
and open documents on next launch. Cosmetic, not data loss.

### Step 6: Crash Reports and Diagnostics

```bash
du -sh ~/Library/Logs/CrashReporter/ ~/Library/Logs/DiagnosticReports/ 2>/dev/null
```

Historical crash data. Ask before clearing:

```bash
rm -rf ~/Library/Logs/CrashReporter/* ~/Library/Logs/DiagnosticReports/*
```

If the user is actively debugging a crash or working with AppleCare, warn
before running — these reports may be needed for diagnosis.

## Phase 5: LaunchAgents (Deep + Audit)

```bash
if [ "$OS_TYPE" != "macos" ]; then
  echo "Phase 5: skipped (macOS only) — detected $OS_TYPE"
  # Stop this phase here. Continue to the next phase.
fi
```

If the guard prints the skip line, stop this phase and move to the next. Do not execute any subsequent `mdfind`/`defaults`/`launchctl`/`xcode-select`/`mas`/`softwareupdate` commands below.

Audit `~/Library/LaunchAgents/`:

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
  # Three-state detection
  target=$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Print :Program" "$plist" 2>/dev/null || echo "UNKNOWN")
  launchctl list 2>/dev/null | grep -q "$label" && load="LOADED" || load="NOT LOADED"
  [ "$target" = "UNKNOWN" ] && tgt="UNKNOWN" || { [ -e "$target" ] && tgt="OK" || tgt="TARGET MISSING"; }
  echo "$label | $load | $tgt"
done
```

For each agent, present a table with columns: plist label, load state (LOADED /
NOT LOADED), target state (OK / TARGET MISSING / UNKNOWN / ORPHANED HOMEBREW SERVICE).
Then prompt: "Remove which? (comma-separated indices, or 'none')" -- per-agent
confirmation is required, no batch removal.

**Exclusions:**
- `homebrew.mxcl.*` agents: managed by `brew services`. Never offer removal.
  Orphaned ones (formula absent from brew list) are reported in the table as
  "ORPHANED HOMEBREW SERVICE" — tell the user to run `brew services cleanup`.
- Agents matching the user's own reverse-DNS domain are almost certainly
  intentional -- present but flag as "user-owned".

**Important**: Many LaunchAgents are NOT tied to .app bundles. Agents for
background services (VPNs, updaters, dev tools) may be critical. When uncertain,
present the plist label and ask -- do not assume safe to remove.

To remove (use label-based target — works on macOS 14+ and older):
```bash
launchctl bootout gui/$(id -u)/<label> 2>/dev/null || \
  launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/<plist>
rm -f ~/Library/LaunchAgents/<plist>
```
The label-based form is the modern target specifier. Fall back to the
plist-path form for agents that didn't load cleanly.

## Phase 6: Xcode & Developer Tools (Deep + Audit)

```bash
if [ "$OS_TYPE" != "macos" ]; then
  echo "Phase 6: skipped (macOS only) — detected $OS_TYPE"
  # Stop this phase here. Continue to the next phase.
fi
```

If the guard prints the skip line, stop this phase and move to the next. Do not execute any subsequent `mdfind`/`defaults`/`launchctl`/`xcode-select`/`mas`/`softwareupdate` commands below.

Run this check first:
```bash
command -v xcode-select >/dev/null 2>&1 && echo "OK" || echo "Phase 6 skipped — Xcode not installed"
```
If the output says "skipped", skip this entire phase.

These can be massive. Check each:

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

## Phase 7: Docker (Deep + Audit)

Run this check first:
```bash
command -v docker >/dev/null 2>&1 && echo "OK" || echo "Phase 7 skipped — Docker not installed"
```
If the output says "skipped", skip this entire phase.

```bash
docker system df 2>/dev/null
```

If Docker is running, report usage and offer cleanup options:
- `docker system prune` — remove dangling images and stopped containers (safe)
- `docker system prune -a` — remove ALL unused images, not just dangling ones.
  **Warn the user**: this removes every image not attached to a running container,
  including ones they may want to reuse. Only suggest if usage is large (>5GB).

If Docker is NOT running but `~/Library/Containers/com.docker.docker/` or
`~/.docker/` exists, report the size as reclaimable orphan data. Note that
Container directories may need elevated privileges. Never run sudo -- surface the
exact command for the user to copy-paste:

```bash
# Remove Docker container data (owned by root)
sudo rm -rf ~/Library/Containers/com.docker.docker/
```

## Phase 8: Project Build Artifacts (all modes)

Discover the user's project directories first. Check common locations:

```bash
for dir in ~/workspace ~/dev ~/Developer ~/code ~/src ~/projects ~/repos ~/Documents; do
  [ -d "$dir" ] && echo "FOUND: $dir"
done
```

Note: `~/Developer` is Apple's recommended project path on macOS 14+.
`~/Documents` may contain projects for non-developers — scan but expect
false positives (e.g., node_modules inside a Documents-hosted Electron
app install). If iCloud Drive is enabled, `~/Documents` syncs — check
sizes carefully before removing.

Use whichever exist. If none found, scan `~` with maxdepth 5 (slower but complete).

Then scan for reclaimable build artifacts:

```bash
# node_modules across all repos (substitute discovered dirs)
find <DIRS> -maxdepth 4 -name "node_modules" -type d -exec du -sh {} + 2>/dev/null | sort -rh

# Python virtual environments
find <DIRS> -maxdepth 4 \( -name ".venv" -o -name "venv" \) -type d -exec du -sh {} + 2>/dev/null | sort -rh

# Build output directories
find <DIRS> -maxdepth 4 \( -name ".next" -o -name "dist" -o -name "build" -o -name "out" -o -name "target" -o -name "__pycache__" -o -name ".mypy_cache" -o -name ".pytest_cache" -o -name ".turbo" -o -name ".nx" -o -name "Pods" -o -name ".build" -o -name "coverage" \) -type d -exec du -sh {} + 2>/dev/null | sort -rh | head -20
```

Report totals. These are all rebuildable — `npm install` / `bun install` / `pip install`
recreates them. But only remove with user approval since it affects project workflow.

For Quick mode: report totals only, don't remove (just awareness).
For Deep mode: offer to remove, noting that next `install` will recreate them.

## Phase 9: Stale Logs (Deep + Audit)

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
> After the Linux journal block, the macOS log scans below run only when `$OS_TYPE = "macos"`.

```bash
if [ "$OS_TYPE" = "macos" ]; then
  ls ~/Library/Logs/ 2>/dev/null
fi
```

Cross-reference against installed apps (same logic as Phase 4).
Flag:
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

## Phase 10: Shell Config Audit (Deep + Audit)

Read `~/.zshrc`, `~/.zprofile`, `~/.zshenv`, `~/.bash_profile` (whichever exist):

1. **Dead PATH entries**: For each PATH addition, check if the target directory exists.
   Flag any that point to uninstalled tools.
2. **Dead aliases**: For each alias, check if the target binary exists.
3. **Dead sources**: For each `source` or `.` command, check if the file exists.
4. **Duplicate PATH entries**: Parse $PATH and flag duplicates.

**Conditional blocks are report-only.** Lines inside `if`/`fi`, `case`/`esac`,
or containing `&& `/`|| ` operators (e.g., `[[ -f ~/.nvm/nvm.sh ]] && source
~/.nvm/nvm.sh`) are never edited or removed -- report as findings only. These
gate on env/hostname/OS; removing them silently breaks workflows.

For lines safe to edit (not inside conditionals):

**Before any edit**, back up: `cp -p <file> <file>.upkeep-bak.$(date +"%Y%m%d-%H%M%S")`
**After each edit**, validate syntax: `zsh -n <file>`. If non-zero exit,
auto-restore from the backup, print a one-line restore notice with the `zsh -n`
stderr output, and abort further edits to that file this session. Note: `zsh -n`
is parse-only -- it catches syntax errors but not missing source targets (Step 3
handles those).

## Phase 11: Electron App Caches (all modes)

```bash
if [ "$OS_TYPE" != "macos" ]; then
  echo "Phase 11: skipped (macOS only) — detected $OS_TYPE"
  # Stop this phase here. Continue to the next phase.
fi
```

If the guard prints the skip line, stop this phase and move to the next. Do not execute any subsequent `mdfind`/`defaults`/`launchctl`/`xcode-select`/`mas`/`softwareupdate` commands below.

For INSTALLED Electron apps only, check for bloated caches:

```bash
# Generic discovery: find Cache/ and Service Worker/ dirs inside Application Support.
# Use maxdepth 5 -- VS Code and other apps nest caches deeper
# (e.g., Code/User/workspaceStorage/<hash>/Cache).
# Exclude Claude's own Application Support dir (protected by rules).
find ~/Library/Application\ Support -maxdepth 5 \
  -not -path "*/Claude/*" -not -path "*/Claude" \
  \( -name "Cache" -o -name "Code Cache" -o -name "Service Worker" -o -name "CachedData" -o -name "CachedExtension*" -o -name "PersistentCache" -o -name "GPUCache" \) \
  -type d -exec du -sh {} + 2>/dev/null | sort -rh | head -15
```

Only show caches over 50MB. These rebuild on next app launch.
**Before offering to clear any app's cache**, check if the app is running:
`pgrep -x "<AppName>" >/dev/null 2>&1`. Use the exact binary name (matches the
Application Support directory name for most Electron apps). If the app IS running,
skip it with: "Electron cache skipped -- <AppName> is running". Do NOT use
`pgrep -f` (matches substrings, causes false positives with system processes).
Only offer cache clearing for apps confirmed not running. After clearing, the app
may take longer on first launch as it rebuilds.

## Phase 12: Large File Scan (Deep + Audit)

Find leftover installers and disk images in the locations users actually
download them to — avoid scanning `~` wholesale (catches iCloud Documents,
syncs, and takes forever):

```bash
find ~/Downloads ~/Desktop -maxdepth 3 \( -name "*.dmg" -o -name "*.pkg" -o -name "*.iso" -o -name "*.zip" \) -not -path "*/.Trash/*" -exec du -sh {} + 2>/dev/null | sort -rh
```

Also check `~/Documents` if the user reports slowness or missing installers
— some users stash downloads there. Offer to remove.

## Phase 13: Trash (all modes)

```bash
du -sh ~/.Trash/ 2>/dev/null
```

Often gigabytes. Safe to empty. Offer:
- `rm -rf ~/.Trash/*` or suggest the user empties via Finder (Cmd+Shift+Delete).

## Phase 14: iPhone / iOS Backups (Deep + Audit)

```bash
if [ "$OS_TYPE" != "macos" ]; then
  echo "Phase 14: skipped (macOS only) — detected $OS_TYPE"
  # Stop this phase here. Continue to the next phase.
fi
```

If the guard prints the skip line, stop this phase and move to the next. Do not execute any subsequent `mdfind`/`defaults`/`launchctl`/`xcode-select`/`mas`/`softwareupdate` commands below.

```bash
du -sh ~/Library/Application\ Support/MobileSync/Backup/ 2>/dev/null
```

Local iPhone/iPad backups can be 50-100GB+. Each subdirectory is one device backup.
List them with dates:

```bash
ls -lht ~/Library/Application\ Support/MobileSync/Backup/ 2>/dev/null
```

Ask the user which (if any) to remove. Warn: "These are local device backups.
If you use iCloud backup, these local copies are redundant. If you don't use
iCloud backup, removing these means you lose your only backup."

## Phase 15: pipx Audit (Deep + Audit)

Run this check first:
```bash
command -v pipx >/dev/null 2>&1 && echo "OK" || echo "Phase 15 skipped — pipx not installed"
```
If the output says "skipped", skip this entire phase.

```bash
pipx list --short 2>/dev/null
```

If pipx is installed, list tools. Ask user if any are unused and can be removed
with `pipx uninstall <tool>`.

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

## Phase 17: Windows Temp Cleanup (WSL2 only)

```bash
if [ "$OS_TYPE" != "wsl2" ]; then
  echo "Phase 17: skipped (WSL2 only) — detected $OS_TYPE"
  # Stop this phase here. Continue to Phase 18.
fi
```

If the guard prints the skip line, stop this phase and move to Phase 18. Do not execute any of the /mnt/c/ commands below.

```bash
if [ ! -d "/mnt/c" ]; then
  echo "Phase 17: /mnt/c not mounted — Windows drive unavailable. Skipping."
else
  _WIN_TEMP="/mnt/c/Users/$USER/AppData/Local/Temp"
  if [ ! -d "$_WIN_TEMP" ]; then
    echo "Phase 17: Windows Temp path not found at $_WIN_TEMP"
    echo "(User may have a different Windows username — skipping)"
  else
    echo "=== Windows Temp size ==="
    du -sh "$_WIN_TEMP" 2>/dev/null || echo "(unable to stat — permission or I/O issue)"
    echo "=== Largest entries inside Windows Temp (top 10) ==="
    du -sh "$_WIN_TEMP"/*/ 2>/dev/null | sort -rh | head -10
  fi
fi
```

> **Windows Temp — approval gate.** If the size is non-trivial (>100MB), prompt: "Clear Windows Temp at /mnt/c/Users/$USER/AppData/Local/Temp/? (yes / no)". On `yes`, run:
>
> ```bash
> rm -rf /mnt/c/Users/"$USER"/AppData/Local/Temp/* 2>/dev/null || true
> ```
>
> This removes only the contents of the Temp directory, not the directory itself — Windows recreates files as needed. Some files may be locked by running Windows processes; the `|| true` swallows those specific failures so the phase keeps going. Never use sudo on /mnt/c/ paths — if a file cannot be removed, surface the path as a findings line and move on. On `no`, skip to Phase 18.

## Phase 18: Windows npm/pip Cache Audit (WSL2 only)

```bash
if [ "$OS_TYPE" != "wsl2" ]; then
  echo "Phase 18: skipped (WSL2 only) — detected $OS_TYPE"
  # Stop this phase here. Continue to Reporting.
fi
```

If the guard prints the skip line, stop this phase and move to Reporting.

```bash
if [ ! -d "/mnt/c" ]; then
  echo "Phase 18: /mnt/c not mounted — Windows drive unavailable. Skipping."
else
  _WIN_NPM="/mnt/c/Users/$USER/AppData/Roaming/npm-cache"
  _WIN_PIP="/mnt/c/Users/$USER/AppData/Local/pip/Cache"
  echo "=== Windows npm-cache ==="
  if [ -d "$_WIN_NPM" ]; then
    du -sh "$_WIN_NPM" 2>/dev/null || echo "(unable to stat)"
  else
    echo "(not present at $_WIN_NPM)"
  fi
  echo "=== Windows pip Cache ==="
  if [ -d "$_WIN_PIP" ]; then
    du -sh "$_WIN_PIP" 2>/dev/null || echo "(unable to stat)"
  else
    echo "(not present at $_WIN_PIP)"
  fi
fi
```

> **Windows package caches — approval gate.** For each cache that is present and non-trivial (>100MB), prompt individually:
>
> - npm-cache: "Clear Windows npm-cache at /mnt/c/Users/$USER/AppData/Roaming/npm-cache/? (yes / no)" → on yes: `rm -rf /mnt/c/Users/"$USER"/AppData/Roaming/npm-cache/* 2>/dev/null || true`
> - pip Cache: "Clear Windows pip Cache at /mnt/c/Users/$USER/AppData/Local/pip/Cache/? (yes / no)" → on yes: `rm -rf /mnt/c/Users/"$USER"/AppData/Local/pip/Cache/* 2>/dev/null || true`
>
> These caches rebuild on next `npm install` / `pip install` invoked from the Windows side. Never use sudo on /mnt/c/ paths — if any file resists removal, surface it as a findings line and move on. Skipping one prompt never skips the other.

## Update Mode

Do not run any cleanup phases. Detect sub-mode: **audit** (check only) | **skills**
(git repos only) | **packages** (package managers only) | **all** (both).
If no sub-mode, ask: A) Audit  B) Skills  C) Packages  D) All

### Step 1: Discover AI Skills (skip for Update Packages)

Check git is installed: `command -v git` — if missing, skip skills section and
note: "Install git: `xcode-select --install`"

**upkeep:** `git -C "${CLAUDE_SKILL_DIR}/../../.." rev-parse --show-toplevel 2>&1`
- Fails → check for `plugin.json`: if present, "managed by plugin manager";
  otherwise "not a git install — re-clone from GitHub". Skip upkeep, continue.
- Succeeds → verify remote: `git -C "${CLAUDE_SKILL_DIR}/../../.." remote get-url origin`
  must contain `KyleNesium/upkeep` or skip with "unexpected remote URL".

**Other Claude skills (discovery-based):**
```bash
for d in ~/.claude/skills/*/; do [ -d "$d/.git" ] && echo "$d"; done
```
For each: `git -C "$d" fetch --tags -q origin 2>/dev/null` then
`git -C "$d" log HEAD..origin/$(git -C "$d" symbolic-ref --short HEAD 2>/dev/null || echo main) --oneline 2>/dev/null`

**Report only (no git):**
- Claude Code marketplace plugins: `ls ~/.claude/plugins/cache/ 2>/dev/null | wc -l`
- Codex skills: `ls ~/.codex/skills/ 2>/dev/null | grep -vc '\.bak$'`

### Step 2: Discover Packages (skip for Update Skills)

Use `command -v <tool>` before each — skip silently if not installed.

```bash
brew outdated 2>/dev/null                                    # count outdated
npm outdated -g 2>/dev/null                                  # list outdated globals
pipx list --short 2>/dev/null                                # installed tools
gem outdated 2>/dev/null                                     # count outdated
rustup check 2>/dev/null                                     # toolchain status
cargo install-update --list 2>/dev/null                      # only if cargo-update installed
command -v uv >/dev/null 2>&1 && uv self version 2>/dev/null
command -v bun >/dev/null 2>&1 && bun --version 2>/dev/null
command -v deno >/dev/null 2>&1 && deno --version 2>/dev/null
command -v mise >/dev/null 2>&1 && mise outdated 2>/dev/null
if [ "$OS_TYPE" = "macos" ]; then
  mas outdated 2>/dev/null                                   # App Store
  softwareupdate -l 2>/dev/null | grep -E "^\s*\*"           # macOS updates
else
  echo "mas: skipped (macOS only)"
  echo "softwareupdate: skipped (macOS only)"
fi
```

### Windows package managers (WSL2 only — audit only)

```bash
if [ "$OS_TYPE" = "wsl2" ]; then
  if [ ! -d "/mnt/c" ]; then
    echo "Windows package managers: /mnt/c not mounted — skipping."
  else
    echo "=== Windows package managers (audit — no upgrades run) ==="
    if command -v winget >/dev/null 2>&1; then
      echo "--- winget ---"
      winget list 2>/dev/null | head -5 || echo "(winget accessible but list failed)"
    else
      echo "winget: not on PATH"
    fi
    if command -v scoop >/dev/null 2>&1; then
      echo "--- scoop ---"
      scoop list 2>/dev/null | head -5 || echo "(scoop accessible but list failed)"
    else
      echo "scoop: not on PATH"
    fi
    if command -v choco >/dev/null 2>&1; then
      echo "--- choco ---"
      choco list 2>/dev/null | head -5 || echo "(choco accessible but list failed)"
    else
      echo "choco: not on PATH"
    fi
  fi
fi
```

> Audit only. This block NEVER runs `winget upgrade`, `scoop update`, or `choco upgrade`. Those require a Windows shell (PowerShell or CMD) — running them from WSL2 has permission and UAC implications that `update` intentionally avoids. When one or more Windows package managers are detected, display this exact guidance after the Windows package manager output:
>
> "To upgrade these, open a Windows PowerShell (as administrator if needed) and run `winget upgrade --all`, `scoop update *`, or `choco upgrade all -y` respectively."

### Step 3: Overview Table

Always present before touching anything:
```
── AI Skills ──────────────────────────────
  upkeep    N commits behind
  gstack       up to date
── Packages ───────────────────────────────
  brew         N outdated      npm globals  N outdated
  pipx         N tools         gems  N outdated
  rustup       <status>        cargo  <status>
  uv           <version>       bun  <version>
  deno         <version>       mise  N outdated
  mas          N outdated      macOS  N updates
── Informational ──────────────────────────
  Claude plugins  N (Claude Code manages)
  Codex skills    N (manual update)
── Windows Packages (WSL2 only — audit only) ──
  winget       N installed  (upgrade via Windows PowerShell)
  scoop        N installed  (upgrade via Windows PowerShell)
  choco        N installed  (upgrade via Windows PowerShell)
```
Omit any row where the tool is not installed.
On Linux or WSL2 (`$OS_TYPE != "macos"`), also omit the `mas` and `macOS` rows — those are macOS-only. The final report in Step 6 shows them as `skipped (macOS only)`.

On macOS or plain Linux, omit the entire "Windows Packages" group — it appears only when `$OS_TYPE = "wsl2"`. For each Windows tool not found via `command -v`, omit that row.

**Update Audit:** stop here. "Audit complete — nothing changed."
If nothing needs updating: "Everything is up to date." — stop.

**Gate 0 (Update All only):**
> "Update N skill(s) + N package category(ies)?
> A) Update all   B) Choose per-category   C) Cancel"

### Step 4: Apply Skill Updates

For each repo with commits behind, show changelog first:
`git -C "$d" log HEAD..origin/<branch> --format="%h %s"` and CHANGELOG.md sections
if present. Ask: "Apply updates to <tool>? A) Yes  B) Skip"

Before pulling, check:
1. `git -C "$d" status --porcelain` — if dirty, show `git status --short` output,
   warn about conflicts, ask "Continue anyway? A) Yes  B) Skip this tool"
2. `git -C "$d" symbolic-ref --quiet HEAD` — if detached, "Run: `git -C <dir> checkout main`
   then retry" — skip this tool, continue others.

Apply: `git -C "$d" pull --ff-only origin <branch> 2>&1`
If non-fast-forward: surface error + "To reset (WARNING — discards local commits):
`cd <dir> && git fetch origin && git reset --hard origin/main`" — never auto-reset.
On success: read `plugin.json` / `VERSION` for old → new version string.

### Step 5: Apply Package Updates

Each category has its own gate. Skipping one does NOT cancel others.

On Linux or WSL2, skip the `mas` and `macOS` rows below — do not run `mas upgrade` or `softwareupdate -ia`. Mark both as `skipped (macOS only)` in the Step 6 final report.

On WSL2, the Step 2 "Windows package managers" block is audit-only — this Step 5 does NOT include winget, scoop, or choco. Upgrades for those require a Windows PowerShell session.

### Linux system packages (apt / dnf / pacman)

Only runs on `$OS_TYPE` of `linux` or `wsl2`. Skipped silently on macOS. Each package manager has its own dry-run preview and approval gate.

```bash
if [ "$OS_TYPE" = "linux" ] || [ "$OS_TYPE" = "wsl2" ]; then
  case "$PKG_MGR" in
    apt)
      echo "=== apt — pending upgrades ==="
      _APT_COUNT=$(apt-get upgrade --dry-run 2>/dev/null | grep -c "^Inst")
      echo "$_APT_COUNT package(s) to upgrade"
      apt-get upgrade --dry-run 2>/dev/null | grep "^Inst" | head -20
      ;;
    dnf)
      echo "=== dnf — pending upgrades ==="
      dnf check-update 2>/dev/null | grep -vE "^(Last metadata|$)" | head -20
      ;;
    pacman)
      echo "=== pacman — pending upgrades ==="
      pacman -Qu 2>/dev/null | head -20
      ;;
    *)
      echo "Linux system packages: unsupported distro ($OS_DISTRO) — skipping"
      ;;
  esac
fi
```

After the preview, ask per-manager:
> "Upgrade system packages via $PKG_MGR? A) Yes  B) Skip $PKG_MGR"

On "Yes", the actual upgrade requires root. Never run these from the skill — surface them as Manual Steps prose for the user to run in their own shell:

> To apply the upgrade, run in your own terminal:
> - apt: `sudo apt-get update && sudo apt-get upgrade -y`
> - dnf: `sudo dnf upgrade -y`
> - pacman: `sudo pacman -Syu --noconfirm`
>
> After the user confirms completion, record the outcome in the Step 6 final report as `apt  ✓ upgraded  N packages` (or `↷ skipped`).

### Snap packages (where installed)

Only runs if `snap` is on `$PATH`. No sudo required for `snap refresh --list`.

```bash
if command -v snap >/dev/null 2>&1; then
  echo "=== snap — pending refreshes ==="
  snap refresh --list 2>/dev/null || echo "(no pending snap refreshes)"
fi
```

Ask:
> "Refresh snap packages? A) Yes  B) Skip snap"

On "Yes", run:

```bash
if command -v snap >/dev/null 2>&1; then
  snap refresh 2>&1
fi
```

Report outcome in Step 6 as `snap  ✓ refreshed  N packages` (or `↷ skipped`). If `snap refresh` exits non-zero with a polkit/authentication error, surface `sudo snap refresh` as a Manual Steps prose line — never re-run from the skill.

### Flatpak applications (where installed)

Only runs if `flatpak` is on `$PATH`. User-scoped flatpak updates do not require root.

```bash
if command -v flatpak >/dev/null 2>&1; then
  echo "=== flatpak — pending updates ==="
  flatpak remote-ls --updates 2>/dev/null | head -20 || flatpak list --app 2>/dev/null | head -10
fi
```

Ask:
> "Update flatpak applications? A) Yes  B) Skip flatpak"

On "Yes", run:

```bash
if command -v flatpak >/dev/null 2>&1; then
  flatpak update -y 2>&1
fi
```

Report outcome in Step 6 as `flatpak  ✓ updated  N apps` (or `↷ skipped`). For system-scoped installs requiring root, surface `sudo flatpak update -y` as a Manual Steps prose line — never run from the skill.

### macOS and cross-platform package managers

| Tool | Audit command | Apply command | Extra warning |
|------|--------------|---------------|---------------|
| brew | `brew outdated` | `brew upgrade` | May affect pinned toolchains |
| npm | `npm outdated -g` | `npm update -g` | |
| pipx | _(list already shown)_ | `pipx upgrade-all` | |
| gems | `gem outdated` | `gem update` | |
| rustup | `rustup check` | `rustup update` | |
| cargo | `cargo install-update --list` | `cargo install-update -a` | Only if cargo-update installed |
| uv | `uv self version` | `uv self update` | Python package manager replacement |
| bun | `bun --version` | `bun upgrade` | |
| deno | `deno --version` | `deno upgrade` | |
| mise | `mise outdated` | `mise upgrade` | Language version manager |
| mas | `mas outdated` | `mas upgrade` | |
| macOS | `softwareupdate -l` | `softwareupdate -ia` | ⚠ Check for `[restart]` in listing — if restart required, warn explicitly before asking |

Gate per category: "Upgrade <tool>? A) Yes  B) Skip <tool>"
macOS with restart: "⚠ This update requires a restart. Save your work.
Apply? A) Yes  B) Skip macOS updates"

### Step 6: Final Report

```
── Update Report ────────────────────────────────
  upkeep   ✓ updated    v1.0.0 → v1.0.1
  gstack   ✓ updated    0.17.0 → 0.18.0
  brew     ✓ upgraded   12 packages
  npm      ↷ skipped
  pipx     ✓ upgraded   2 tools
  bun      ✓ upgraded   1.1.0 → 1.2.0
  mise     ✓ upgraded   3 runtimes
  mas      ✓ upgraded   1 app
  apt      ✓ upgraded   N packages   (Linux/WSL2 only)
  snap     ✓ refreshed  N packages   (if installed)
  flatpak  ✓ updated    N apps       (if installed)
── Informational ────────────────────────────────
  Claude plugins  9  (managed by Claude Code)
  Codex skills   12  (manual update required)
```
Omit rows for tools not installed on this machine.

## Reporting

### Per-phase reporting

After each phase, report findings in a short table. Ask before taking action.
Batch removals by phase — don't ask per-file unless it's ambiguous (like which
brew packages to remove).

### Final Summary

After all phases complete, present the cumulative report:

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
| 16| Snap & Flatpak | ... | ...MB | Cleaned / Skipped |
| 17| Windows Temp (WSL2) | ... | ...MB | Cleaned / Skipped |
| 18| Windows npm/pip (WSL2) | ... | ...MB | Cleaned / Skipped |
| **Total** | | | **...GB** | |
```

### Before/After

```bash
diskutil info / 2>/dev/null | grep -E "Free|Available|Purgeable" || df -h / | tail -1
```

Compare against Phase 1 baseline. Report Available and Purgeable separately:

```
Disk before: XXX available (YYY purgeable)
Disk after:  XXX available (YYY purgeable)
Reclaimed:   ~ZZZ
```

macOS keeps recently deleted data as "purgeable" — Finder may not show freed space immediately because it reclaims on demand.

## Rules

- NEVER remove data for apps that ARE currently installed in /Applications
- NEVER touch `~/Library/Application Support/Claude/` or `~/.claude/`
- NEVER remove Apple system directories (`com.apple.*`)
- NEVER remove `~/Library/Keychains/`, `~/Library/Preferences/` contents
- ALWAYS report sizes before removing anything
- ALWAYS unload LaunchAgents before deleting their plist files
- NEVER remove homebrew.mxcl.* LaunchAgents -- these are managed by `brew services`
- ALWAYS ask before removing brew packages, LaunchAgents, or ambiguous items
- For caches: batch approval is fine ("clear all dev caches?")
- Never execute sudo, never pipe to sudo, never offer to "run it for you".
  When an operation needs elevated privileges, surface the exact command in
  a fenced bash code block with a one-line rationale comment. Display both
  inline at the phase where it occurs AND in the final report under a
  "## Manual Steps" section.
- Track cumulative space reclaimed and report the total at the end
- In Quick mode, skip non-Quick phases — get in and out fast
- In Audit mode, never offer removal — report findings and sizes only
