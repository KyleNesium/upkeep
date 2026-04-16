---
name: upkeep:update
version: 1.0.6
author: KyleNesium
description: |
  Update AI skills and package managers in one sweep. Discovers what's outdated
  across git-based skills and package managers, then upgrades with per-category
  confirmation gates. Four sub-modes: audit (check only), skills (git-pull all
  AI skills), packages (upgrade brew, npm, pip, gems, rustup, mas, macOS),
  all (skills then packages).
  Use when: "update upkeep", "update my AI skills", "update everything",
  "check for updates", "upgrade my packages", "update all my tools",
  "is upkeep up to date", "self-update", "upgrade brew", "update skills".
allowed-tools:
  # Read-only discovery / queries
  - Bash(echo *)
  - Bash(date *)
  - Bash(command *)
  - Bash(which *)
  - Bash(ls *)
  - Bash(stat *)
  - Bash(wc *)
  - Bash(grep *)
  - Bash(cut *)
  # Package manager audit commands
  - Bash(brew *)
  - Bash(npm *)
  - Bash(pipx *)
  - Bash(gem *)
  - Bash(rustup *)
  - Bash(cargo *)
  - Bash(mas *)
  - Bash(softwareupdate *)
  # Git ops (scoped to specific subcommands, never global git ops)
  - Bash(git -C * rev-parse *)
  - Bash(git -C * status *)
  - Bash(git -C * fetch *)
  - Bash(git -C * log *)
  - Bash(git -C * pull *)
  - Bash(git -C * remote *)
  - Bash(git symbolic-ref *)
  - Bash(git -C * symbolic-ref *)
  - Read
  - Glob
---

# /upkeep:update — Update AI Skills & Package Managers

You are a macOS update specialist. Discover what's outdated across AI skills and
package managers, then upgrade with per-category confirmation gates.

Do not run any cleanup phases. Detect sub-mode from the user's request:
- **audit** — check only, no changes
- **skills** — git repos only
- **packages** — package managers only
- **all** — both skills and packages

If no sub-mode is specified, ask:
> A) Audit — check what's outdated, no changes
> B) Skills — update AI skills only
> C) Packages — upgrade package managers only
> D) All — skills first, then packages

Announce (`Mode: Update / <sub-mode>`) before proceeding.

## Step 1: Discover AI Skills (skip for Update Packages)

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

## Step 2: Discover Packages (skip for Update Skills)

Use `command -v <tool>` before each — skip silently if not installed.

```bash
brew outdated 2>/dev/null
npm outdated -g 2>/dev/null
pipx list --short 2>/dev/null
gem outdated 2>/dev/null
rustup check 2>/dev/null
cargo install-update --list 2>/dev/null
command -v uv >/dev/null 2>&1 && uv self version 2>/dev/null
command -v bun >/dev/null 2>&1 && bun --version 2>/dev/null
command -v deno >/dev/null 2>&1 && deno --version 2>/dev/null
command -v mise >/dev/null 2>&1 && mise outdated 2>/dev/null
mas outdated 2>/dev/null
softwareupdate -l 2>/dev/null | grep -E "^\s*\*"
```

## Step 3: Overview Table

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

## Step 4: Apply Skill Updates

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

## Step 5: Apply Package Updates

Each category has its own gate. Skipping one does NOT cancel others.

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

## Step 6: Final Report

```
── Update Report ────────────────────────────────
  upkeep   ✓ updated    v1.0.0 → v1.0.1
  gstack   ✓ updated    0.17.0 → 0.18.0
  brew     ✓ upgraded   12 packages
  npm      ↷ skipped
  pipx     ✓ upgraded   2 tools
  mas      ✓ upgraded   1 app
── Informational ────────────────────────────────
  Claude plugins  9  (managed by Claude Code)
  Codex skills   12  (manual update required)
```

## Rules

- Never run sudo
- Never auto-reset dirty repos — always ask first
- Never auto-reset non-fast-forward pulls — surface the command for the user
- Each package category has its own confirmation gate — skipping one never skips others
- macOS updates with `[restart]` always get an explicit restart warning before running
