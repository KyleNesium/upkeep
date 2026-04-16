---
name: upkeep
version: 1.0.0
author: KyleNesium
description: |
  macOS system cleanup. Three modes: deep (full 15-phase audit + cleanup),
  quick (caches + brew), audit (report only, no changes). Discovery-based
  orphan detection, before/after disk tracking. Handles Homebrew, dev caches,
  orphaned app data, LaunchAgents, Xcode, Docker, build artifacts, Electron,
  shell config, logs, large files, iOS backups, and pipx tools.
  Use when: "clean up my mac", "disk cleanup", "free up space", "audit my mac",
  "what's taking up space", "new machine setup", "mac cleanup".
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
  # Update mode — package manager upgrades (new: rustup, mas, softwareupdate)
  - Bash(rustup *)
  - Bash(mas *)
  - Bash(softwareupdate *)
---

# /clean — macOS System Cleanup

You are a macOS system cleanup specialist. Audit the machine for reclaimable disk
space, stale data, and configuration issues. Clean up with user approval.

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

**Quick phases:** 1, 2, 3, 8, 11, 13. **Deep/Audit phases:** All 15.
Audit never offers removal — report findings and sizes only.
Tag each phase header with `(Deep)`, `(Quick)`, or `(Audit)`.

## Phase 1: Baseline (all modes)

Run first in both modes. Record the starting disk state for before/after comparison.

```bash
echo "=== Disk ===" && diskutil info / 2>/dev/null | grep -E "Free|Available|Purgeable" || df -h / | tail -1
echo "=== macOS ===" && sw_vers
echo "=== Homebrew ===" && brew --version 2>/dev/null || echo "not installed"
```

Capture the "Available" and "Purgeable" values from `diskutil info`.
APFS volumes have purgeable space that `df` doesn't distinguish — use `diskutil`
for accurate before/after. Fall back to `df` if `diskutil` is unavailable.

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

If the nudge fires, display it once at the top before phase output. Then continue cleanup normally.

## Phase 2: Homebrew Audit (all modes)

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
5. `brew leaves` — top-level packages. Present the list and ask if any should go.
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

Audit `~/Library/LaunchAgents/`:

```bash
for plist in ~/Library/LaunchAgents/*.plist; do
  [ -f "$plist" ] || continue
  label=$(basename "$plist" .plist)
  # Skip Homebrew-managed agents
  [[ "$label" == homebrew.mxcl.* ]] && continue
  # Three-state detection
  target=$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Print :Program" "$plist" 2>/dev/null || echo "UNKNOWN")
  launchctl list 2>/dev/null | grep -q "$label" && load="LOADED" || load="NOT LOADED"
  [ "$target" = "UNKNOWN" ] && tgt="UNKNOWN" || { [ -e "$target" ] && tgt="OK" || tgt="TARGET MISSING"; }
  echo "$label | $load | $tgt"
done
```

For each agent, present a table with columns: plist label, load state (LOADED /
NOT LOADED), target state (OK / TARGET MISSING / UNKNOWN). Then prompt:
"Remove which? (comma-separated indices, or 'none')" -- per-agent confirmation
is required, no batch removal.

**Exclusions:**
- `homebrew.mxcl.*` agents: managed by `brew services`. Never offer removal.
  If the matching formula is missing from `brew list --formula`, report it as
  "orphaned homebrew service -- run `brew services cleanup` to remove" but do
  not remove it directly.
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
| CoreSimulator | Partially | `xcrun simctl delete unavailable` removes stale ones safely. |

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
find <DIRS> -maxdepth 4 \( -name ".next" -o -name "dist" -o -name "build" -o -name "__pycache__" -o -name ".mypy_cache" -o -name ".pytest_cache" -o -name ".turbo" \) -type d -exec du -sh {} + 2>/dev/null | sort -rh | head -20
```

Report totals. These are all rebuildable — `npm install` / `bun install` / `pip install`
recreates them. But only remove with user approval since it affects project workflow.

For Quick mode: report totals only, don't remove (just awareness).
For Deep mode: offer to remove, noting that next `install` will recreate them.

## Phase 9: Stale Logs (Deep + Audit)

```bash
ls ~/Library/Logs/ 2>/dev/null
```

Cross-reference against installed apps (same logic as Phase 4).
Flag:
1. Log directories from uninstalled apps
2. Rotated log files: `*.old.*`, `*.log.N`, `*.log.old`
3. Any single log file over 10MB

## Phase 10: Shell Config Audit (Deep + Audit)

Read `~/.zshrc`, `~/.zprofile`, `~/.bash_profile` (whichever exist):

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

For INSTALLED Electron apps only, check for bloated caches:

```bash
# Generic discovery: find Cache/ and Service Worker/ dirs inside Application Support.
# Use maxdepth 5 -- VS Code and other apps nest caches deeper
# (e.g., Code/User/workspaceStorage/<hash>/Cache).
find ~/Library/Application\ Support -maxdepth 5 \( -name "Cache" -o -name "Code Cache" -o -name "Service Worker" -o -name "CachedData" -o -name "CachedExtension*" -o -name "PersistentCache" -o -name "GPUCache" \) -type d -exec du -sh {} + 2>/dev/null | sort -rh | head -15
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
find ~/Downloads ~/Desktop -maxdepth 3 \( -name "*.dmg" -o -name "*.pkg" -o -name "*.iso" -o -name "*.zip" \) -not -path "*/.Trash/*" 2>/dev/null
```

Also check `~/Documents` if the user reports slowness or missing installers
— some users stash downloads there. Report with sizes. Offer to remove.

## Phase 13: Trash (all modes)

```bash
du -sh ~/.Trash/ 2>/dev/null
```

Often gigabytes. Safe to empty. Offer:
- `rm -rf ~/.Trash/*` or suggest the user empties via Finder (Cmd+Shift+Delete).

## Phase 14: iPhone / iOS Backups (Deep + Audit)

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

## Update Mode

Do not run any cleanup phases. Detect sub-mode: **audit** (check only) | **skills**
(git repos only) | **packages** (package managers only) | **all** (both).
If no sub-mode, ask: A) Audit  B) Skills  C) Packages  D) All

### Step 1: Discover AI Skills (skip for Update Packages)

Check git is installed: `command -v git` — if missing, skip skills section and
note: "Install git: `xcode-select --install`"

**upkeep:** `git -C "${CLAUDE_SKILL_DIR}/../../.." rev-parse --show-toplevel 2>&1`
- Fails → check for `.git`: if plugin.json exists, "managed by plugin manager";
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
mas outdated 2>/dev/null                                     # App Store
softwareupdate -l 2>/dev/null | grep -E "^\s*\*"             # macOS updates
```

### Step 3: Overview Table

Always present before touching anything:
```
── AI Skills ──────────────────────────────
  upkeep    N commits behind
  gstack       up to date
── Packages ───────────────────────────────
  brew         N outdated
  npm globals  N outdated    pipx  N tools
  gems         N outdated    rustup  <status>
  mas          N outdated    macOS  N updates
── Informational ──────────────────────────
  Claude plugins  N (Claude Code manages)
  Codex skills    N (manual update)
```
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
2. `git symbolic-ref --quiet HEAD` — if detached, "Run: `git -C <dir> checkout main`
   then retry" — skip this tool, continue others.

Apply: `git -C "$d" pull --ff-only origin <branch> 2>&1`
If non-fast-forward: surface error + "To reset (WARNING — discards local commits):
`cd <dir> && git fetch origin && git reset --hard origin/main`" — never auto-reset.
On success: read `plugin.json` / `VERSION` for old → new version string.

### Step 5: Apply Package Updates

Each category has its own gate. Skipping one does NOT cancel others.

| Tool | Audit command | Apply command | Extra warning |
|------|--------------|---------------|---------------|
| brew | `brew outdated` | `brew upgrade` | May affect pinned toolchains |
| npm | `npm outdated -g` | `npm update -g` | |
| pipx | _(list already shown)_ | `pipx upgrade-all` | |
| gems | `gem outdated` | `gem update` | |
| rustup | `rustup check` | `rustup update` | |
| cargo | `cargo install-update --list` | `cargo install-update -a` | Only if cargo-update installed |
| mas | `mas outdated` | `mas upgrade` | |
| macOS | `softwareupdate -l` | `softwareupdate -ia` | ⚠ Check for `[restart]` in listing — if restart required, warn explicitly before asking |

Gate per category: "Upgrade <tool>? A) Yes  B) Skip <tool>"
macOS with restart: "⚠ This update requires a restart. Save your work.
Apply? A) Yes  B) Skip macOS updates"

### Step 6: Final Report

```
── Update Report ────────────────────────────────
  upkeep   ✓ updated    v1.0.0 → v1.0.1
  gstack      ✓ updated    0.17.0 → 0.18.0
  brew        ✓ upgraded   12 packages
  npm         ↷ skipped
  pipx        ✓ upgraded   2 tools
  mas         ✓ upgraded   1 app
── Informational ────────────────────────────────
  Claude plugins  9  (managed by Claude Code)
  Codex skills   12  (manual update required)
```

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
