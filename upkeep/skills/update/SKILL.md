---
name: upkeep:update
version: 1.5.0
author: KyleNesium
description: |
  Update AI skills and package managers in one sweep. On macOS, the v1.5
  fast path collapses discovery, plan synthesis, apply orchestration,
  post-flight checks, and failure diagnosis into one shell script
  (`scripts/update.sh`). The skill is a thin two-turn wrapper: turn 1
  builds the plan and renders the approval gate; turn 2 runs apply and
  renders the report. brew metadata is TTL-cached (1h default) so warm
  runs hit the gate in <5s. The failure-diagnoser LLM agent from v1.3
  is now a deterministic pattern table (`scripts/diagnose.sh`).
  Enrichment (changelog summaries + project impact) is opt-in behind
  `--advisor`. Linux & WSL2 still use the v1.0 sequential flow (port
  scheduled for v1.6). Sub-modes: audit (no changes), skills (git-pull
  AI skills), packages (package managers only), all.
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
  - Bash(awk *)
  - Bash(sort *)
  - Bash(head *)
  - Bash(tail *)
  - Bash(basename *)
  - Bash(xargs *)
  - Bash(find *)
  - Bash(jq *)
  - Bash(df *)
  - Bash(mkdir *)
  - Bash(mv *)
  - Bash(rm *)
  # OS detection (cross-platform)
  - Bash(uname *)
  - Bash(lsb_release *)
  - Bash(lsblk *)
  - Bash(cat *)
  # Package manager audit + apply commands
  - Bash(brew *)
  - Bash(npm *)
  - Bash(pipx *)
  - Bash(gem *)
  - Bash(rustup *)
  - Bash(cargo *)
  - Bash(mas *)
  - Bash(softwareupdate *)
  - Bash(bun *)
  - Bash(deno *)
  - Bash(mise *)
  - Bash(uv *)
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
  - Grep
  - Agent
  - WebFetch  # v1.5: only used in --advisor mode
  # Linux system tools
  - Bash(systemctl *)
  - Bash(journalctl *)
  # Linux package managers
  - Bash(apt *)
  - Bash(dnf *)
  - Bash(pacman *)
  - Bash(snap *)
  - Bash(flatpak *)
  # Windows package managers (WSL2 audit only — never invoke upgrade commands)
  - Bash(winget *)
  - Bash(scoop *)
  - Bash(choco *)
---

# /upkeep:update — Update AI Skills & Package Managers

You are a macOS update specialist. Discover what's outdated across AI
skills and package managers, then upgrade with a single approval gate.

### Hard Rule: plan and apply are separate turns

The macOS fast path is exactly two LLM turns:

1. **Plan turn:** run `update.sh plan <mode>`, render the gate, end the
   turn at the `AskUserQuestion`.
2. **Apply turn:** on approval, run `update.sh apply <plan-file>`, render
   the report.

Never print "Apply?" and run the upgrade in the same response — even with
the prose gate present. Audit mode never reaches an apply step.

The Linux/WSL2 sequential flow (Steps 1–6 at the bottom) has the same
hard rule: each per-category gate ends the turn at the
`AskUserQuestion`.

Detect sub-mode from the user's request:
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

## Environment Detection

Run this FIRST, before any step. It sets `$OS_TYPE` (macos / linux / wsl2), `$OS_DISTRO`, and `$PKG_MGR` — Step 2 and Step 5 of the Linux flow gate `mas` and `softwareupdate` on `$OS_TYPE = "macos"`.

```bash
# ── OS Detection (run once, export for all steps) ────────────────
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

If `$OS_TYPE` is `unknown`, report "Update skill requires macOS, Linux, or WSL2. Detected: $(uname -s)" and stop.

## Routing

```
if $OS_TYPE = "macos":
   → run the macOS Fast Path below (Turn 1 + Turn 2)
   → skip the v1.0 Sequential Flow (Steps 1–6)
else:
   → skip the macOS Fast Path
   → run the v1.0 Sequential Flow (Steps 1–6, unchanged for Linux/WSL2)
```

Linux/WSL2 fast-path port is scheduled for v1.6.

---

## macOS Fast Path (v1.5)

### Turn 1: Plan

Disk pre-flight first (sub-second):

```bash
FREE_GB=$(df -k / 2>/dev/null | awk 'NR==2 {print int($4/1024/1024)}')
if [ -z "$FREE_GB" ] || [ "$FREE_GB" -lt 5 ]; then
  echo "✗ Refusing to start: only ${FREE_GB:-?} GB free on /. Free up at least 5 GB and re-run."
  exit 1
elif [ "$FREE_GB" -lt 10 ]; then
  echo "⚠ Warning: only ${FREE_GB} GB free on /."
fi
```

Then build the plan in one call. `$SKILL_DIR` is the directory containing
this SKILL.md — the harness tells you the absolute path when the skill
loads; use it as a literal in the command:

```bash
# Replace <SKILL_DIR> with the absolute path the harness reported.
PLAN_RENDER=$(bash <SKILL_DIR>/scripts/update.sh plan "$MODE")
```

The script:
1. Runs `scripts/discover.sh` (with `brew update` TTL-cached for 1h).
2. Runs `scripts/synthesize.sh` to build the plan.
3. Writes the full plan to a temp file in `~/.claude/data/`.
4. Prints SKILL.md-facing JSON to stdout: `{plan_file, needs_approval,
   summary, warnings, manual_steps, ordered_groups, restart_required,
   untrusted_repos}`.

Honor the JSON in this order:

#### A. Untrusted skill repos (skill trust gate)

If `untrusted_repos[]` is non-empty, surface each via `AskUserQuestion`
**before** the main approval gate. Per repo:

> Skill `<name>` at `<path>` has remote `<url>`. Fetch updates from it?
> A) Trust this remote (remember for future runs)
> B) Skip this skill this run
> C) Show recent commits from origin first

On A, append the URL to `~/.claude/data/upkeep-skill-trust.json` and
re-run `update.sh plan <MODE>` so the new plan reflects the trusted
fetch. On B, leave it for `manual_steps`. On C, run
`git ls-remote <url>` and re-prompt A/B.

This gate is its own turn — end at the `AskUserQuestion`.

#### B. Audit-mode short-circuit

If `needs_approval == false` AND `mode == "audit"`:

Render the plan compactly as a report (no apply). Stop.

#### C. Nothing-to-do short-circuit

If `needs_approval == false` for any other reason (empty
`ordered_groups`):

Render `Everything is up to date.` Surface any `manual_steps[]` as
informational. Stop.

#### D. Approval gate render

Otherwise render the plan as the gate. Use this layout, populated from
the JSON:

```
Plan:
  Skills (N):     <git_repos applied> (from manual_steps for dirty/untrusted)
  brew  (N):      ⚠ major: <names> | minor: <count> | patch: <count>
  npm   (N):      <names>
  pipx  (N):      <names>
  gems  (N):      <major bumps>     [--user-install: gems_user_install=true]
  uv    (self):   <from> → latest
  bun   (self):   <from> → latest
  mas   (N):      <names>
  macOS (N):      <updates>          [restart] if restart_required=true

Risks flagged:
  • <one line per warnings[] entry, severity-ordered>

Manual steps (after apply):
  • <one line per manual_steps[] entry>

ETA: ~<summary.eta_minutes_p50>m (p50), up to <eta_minutes_p90>m (p90)
Disk free: <summary.disk_free_gb> GB
```

Then the single `AskUserQuestion`:
- A) Apply all
- B) Drop categories
- C) Cancel

If "Drop categories", a second multi-select `AskUserQuestion` with one
option per `ordered_groups[].name`. Collect the dropped tool ids
(e.g. `brew,gems`) as `$DROP_CSV`.

If `restart_required == true` and macOS wasn't dropped:
> ⚠ This update requires a restart. Save your work.
> Apply? A) Yes  B) Skip macOS updates
(B adds `macos` to `$DROP_CSV`.)

**End the turn at the `AskUserQuestion`.** Do not proceed in the same
response.

### Turn 2: Apply

On approval, in a new turn (use the same `<SKILL_DIR>` literal as Turn 1
and the `plan_file` path returned by the plan call):

```bash
REPORT=$(bash <SKILL_DIR>/scripts/update.sh apply "$PLAN_FILE" \
  ${DROP_CSV:+--drop="$DROP_CSV"})
```

The script:
1. Reads the plan from `$PLAN_FILE`.
2. Runs the skills apply phase (path-validated, dirty-skipped, ff-only).
3. Runs the package dispatcher (hardcoded commands, never `eval` plan).
4. Runs post-flight (`brew doctor`, PATH-shadow re-check, resolution
   re-check, deprecation aggregator).
5. Runs `scripts/diagnose.sh` against any failures (pattern table —
   replaces the v1.3 `failure-diagnoser` agent).
6. Writes history (flock-guarded).
7. Removes the plan file.
8. Prints SKILL.md-facing JSON: `{mode, skills, upgraded_formulas,
   upgraded_tools, doctor, shadow_hits, resolution_failures, diagnoses,
   diagnosis_errors}`.

#### Report render

Render the JSON as the final report:

```
── ⚠ Failures observed ────────────────────────────────  (if diagnoses[] non-empty)
  • <tool> [<severity>]: <root_cause>
    Failing: <comma-separated failing_items>
    Suggested fixes (copy to run yourself — NOT auto-executed):
      A) <label>
         $ <command>
      B) <label>
         $ <command>

── Update Report ───────────────────────────────────────
  Skills   ✓ applied <N> / skipped <M>     (from .skills)
  brew     ✓ upgraded <N> packages         (from .upgraded_formulas)
  npm      <symbol> <result>                (from .upgraded_tools)
  pipx     <symbol> <result>
  gems     <symbol> <result>
  uv       <symbol> <result>
  bun      <symbol> <result>
  mas      —             (only if installed)
  macOS    <symbol> <result>

── Post-flight ─────────────────────────────────────────
  • brew doctor: <.doctor or "clean">
  • PATH shadows: <.shadow_hits[] or "none">
  • Resolution failures: <.resolution_failures[] or "none">
```

The `$ <command>` lines in the failures block are **text only** — never
auto-execute them in the same turn or any subsequent turn without an
explicit user instruction. The `$` prefix and "copy to run yourself"
label are part of the contract.

#### Apply failure handling

If `update.sh apply` exits non-zero, surface the error JSON's `error`
field and stop. Do not retry — the user re-invokes manually.

### Optional: `--advisor` enrichment (opt-in)

Default: no enrichment. Plan shows raw version bumps + compat-matrix
warnings only. Gate appears fast (<5s on warm cache).

If the user explicitly requests advisor mode (`/upkeep:update <mode>
--advisor`):

1. Plan turn renders the gate WITHOUT enrichment (same as default).
2. Apply turn fans out two Agent calls IN PARALLEL with `update.sh
   apply`:
   - `changelog-reader` (filtered to major brew bumps + compat-matrix
     materialised at medium+ severity, capped at 8 items).
   - `project-impact` (scans `$HOME/workspace`, `$HOME/Github`,
     `$HOME/Projects`, `$HOME/src`, `$HOME/code`, `$HOME/dev` if they
     exist; cap 200 repos / 50 hits).
3. Wait for both agents AND `update.sh apply` to complete.
4. Merge enrichment into the final report under
   `Release notes (advisor)` and `Affects your projects` sections.

The agent prompts and sanitization JQ from v1.3/v1.4 are unchanged.
They live behind the `--advisor` flag because their WebFetch + manifest
walks add 30–60s and most users want speed over the upfront context.

### Hard rules (preserved from v1.4)

- Apply commands are hardcoded inside `scripts/update.sh`'s dispatcher.
  Plan JSON's `tool_specs[].command` and `.preconditions` fields are
  **never** read — the script strips them silently.
- Tool ids are validated against the allowlist `skills brew npm pipx
  gems uv bun mas macos` before any dispatcher call.
- Discovery JSON sanitization (256-char string cap + free-text denylist)
  runs inside `discover.sh` before its output reaches the synthesizer.
- Skills git pulls are path-validated to `~/.claude/skills/*` or
  `~/.codex/skills/*`, dirty trees are skipped, detached HEAD is skipped,
  pulls are `--ff-only`.
- `update.sh` strict-mode aborts on bad mktemp / missing jq — the
  orchestrator never runs on a half-initialized state.
- The `failure-diagnoser` pattern table emits the same JSON shape as the
  v1.4 agent; destructive-command denylist
  (`rm -rf|--force|sudo rm|chmod 777|push --force|curl|sh`) runs as
  defense-in-depth inside `diagnose.sh` even though patterns are hand-
  authored.

### Environment knobs

| Variable | Default | Effect |
|---|---|---|
| `UPKEEP_BREW_TTL` | 3600 | `brew update` cache TTL in seconds |
| `UPKEEP_NO_CACHE` | unset | Set to `1` to force `brew update` refresh |
| `UPKEEP_DATA_DIR` | `~/.claude/data` | Plan + history directory |
| `UPKEEP_TRUST_FILE` | `~/.claude/data/upkeep-skill-trust.json` | Skill repo trust list |

---

## Step 1: Discover AI Skills (skip for Update Packages)

> **Routing reminder.** Steps 1–6 below are the v1.0 sequential flow used on
> Linux and WSL2. On macOS, the parallel flow above (Steps 1m–5m) replaces
> Steps 1–6 entirely — do not run both. If `$OS_TYPE = "macos"` you should
> already have produced the final report; skip the rest of this file.

Check git is installed: `command -v git` — if missing, skip skills section and
note: "Install git: `xcode-select --install`"

**upkeep:** `git -C "${CLAUDE_SKILL_DIR}/../../.." rev-parse --show-toplevel 2>&1`
- Fails → check for `plugin.json`: if present, "managed by plugin manager";
  otherwise "not a git install — re-clone from GitHub". Skip upkeep, continue.
- Succeeds → verify remote with an exact host+path match (substring match
  was previously vulnerable to URLs like `https://evil.example/?KyleNesium/upkeep`):
  ```bash
  ORIGIN_URL=$(git -C "${CLAUDE_SKILL_DIR}/../../.." remote get-url origin 2>/dev/null)
  case "$ORIGIN_URL" in
    https://github.com/KyleNesium/upkeep|\
    https://github.com/KyleNesium/upkeep.git|\
    git@github.com:KyleNesium/upkeep|\
    git@github.com:KyleNesium/upkeep.git)
      ;;
    *)
      echo "Skipping upkeep: unexpected remote URL: $ORIGIN_URL"
      ;;
  esac
  ```
  Only the four canonical forms above are accepted. Anything else skips.

**Other Claude skills (discovery-based):**
```bash
for d in ~/.claude/skills/*/; do [ -d "$d/.git" ] && echo "$d"; done
```

**First-encounter approval for third-party skill repos.** Before fetching,
build a per-skill record showing the remote URL and (if available) the most
recent tagged version. Read `~/.claude/data/upkeep-skill-trust.json` for
prior approvals; for any new remote URL, surface it via `AskUserQuestion`:

> Skill `<name>` at `<path>` has remote `<url>`. Fetch updates from it?
> A) Trust this remote (remember for future runs)
> B) Skip this skill

v1.3.1: this gate matches the macOS flow's storage format and option set
exactly. The trust file is **keyed by exact-match remote URL** (NOT by
repo path) so a trust decision survives the user moving the skill between
directories and does not transfer trust if they re-clone a different
remote at the same path. The pre-1.3.1 path-keyed Linux/WSL2 format would
have caused trust drift between the two flows — a remote trusted on
macOS would not be honored on Linux against the same skill, and vice
versa.

On A, append to `upkeep-skill-trust.json` keyed by the remote URL.
Do not fetch from a remote that has not been explicitly trusted. This makes
the supply-chain trust decision visible and reversible (delete the entry to
re-prompt) instead of implicit.

For each trusted skill: `git -C "$d" fetch --tags -q origin 2>/dev/null` then
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

## Step 3: Overview Table

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
On Linux or WSL2 (`$OS_TYPE != "macos"`), also omit the `mas` and `macOS` rows — those are macOS-only. The final report in Step 6 shows them as `skipped (macOS only)` so the user sees they were intentionally excluded.

On macOS or plain Linux, omit the entire "Windows Packages" group — it appears only when $OS_TYPE = "wsl2". For each Windows tool not found via command -v, omit that row. Windows package managers are labeled "audit only" because update never invokes winget upgrade, scoop update, or choco upgrade — surface guidance for the user to run those from a Windows shell instead.

**Update Audit:** stop here. "Audit complete — nothing changed."
If nothing needs updating: "Everything is up to date." — stop.

**Gate 0 (Update All only):**
> "Update N skill(s) + N package category(ies)?
> A) Update all   B) Choose per-category   C) Cancel"

v1.3.1: "Choose per-category" is **intent only**. End this turn at Gate 0.

- On `A) Update all`, proceed to Step 4 in the next turn against every
  category surfaced in Step 3's overview table.
- On `B) Choose per-category`, end this turn at a second multi-select
  `AskUserQuestion` with one option per category (skills, brew, npm,
  pipx, gems, uv, bun, mas, macOS, apt, dnf, pacman, snap, flatpak —
  only the ones that returned non-empty discovery in Step 3). End the
  turn again. In the next turn re-render the overview table filtered
  to the user's selection and end at a final
  `Apply filtered plan / Cancel` `AskUserQuestion`. Proceed to Step 4
  only on `Apply filtered plan`.
- On `C) Cancel`, stop here.

The three-gate shape matches the macOS Step 3m approval gate so Linux
users see the same "every Apply is bracketed by the exact plan summary
just shown" contract. Pre-1.3.1, the Linux flow specified Option B
without defining what should happen next, so the LLM was free to apply
immediately after the multi-select with stale overview context.

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

On Linux or WSL2, skip the `mas` and `macOS` rows below — do not run `mas upgrade` or `softwareupdate -ia`. Mark both as `skipped (macOS only)` in the Step 6 final report.

On WSL2, the Step 2 "Windows package managers" block is audit-only — this Step 5 table does NOT include winget, scoop, or choco. Upgrades for those require a Windows PowerShell session and are intentionally out of scope for update. The Step 6 final report lists each detected Windows package manager under "Windows Packages" with status "audit only" so the skip is visible rather than silent.

### Linux system packages (apt / dnf / pacman)

Only runs on `$OS_TYPE` of `linux` or `wsl2`. Skipped silently on macOS. Each package manager has its own dry-run preview and approval gate — skipping one never affects the snap/flatpak gates that follow.

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

Only runs if `snap` is on `$PATH`. No sudo required for `snap refresh --list`; `snap refresh` itself may prompt for authentication via polkit on Linux — that prompt appears in the user's own terminal session.

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

Report outcome in Step 6 as `snap  ✓ refreshed  N packages` (or `↷ skipped`). If `snap refresh` exits non-zero with a polkit/authentication error, surface the exact command for the user to run manually (`sudo snap refresh`) as a Manual Steps prose line — never re-run from the skill.

### Flatpak applications (where installed)

Only runs if `flatpak` is on `$PATH`. Flatpak updates do not require root when the flatpak runtime is user-scoped; system-scoped updates require root and are surfaced as Manual Steps only.

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
  bun      ✓ upgraded   1.1.0 → 1.2.0
  mise     ✓ upgraded   3 runtimes
  mas      ✓ upgraded   1 app
  apt      ✓ upgraded   N packages     (Linux only)
  snap     ✓ refreshed  N packages     (where installed)
  flatpak  ✓ updated    N apps         (where installed)
── Informational ────────────────────────────────
  Claude plugins  9  (managed by Claude Code)
  Codex skills   12  (manual update required)
── Windows Packages (WSL2 only) ─────────────────
  winget   ⓘ audit only    N installed
  scoop    ⓘ audit only    N installed
  choco    ⓘ audit only    N installed
```
Omit rows for tools not installed on this machine.
On Linux or WSL2, show both `mas  ↷ skipped (macOS only)` and `macOS  ↷ skipped (macOS only)` rows in the report so the skip is visible rather than silent.
On Linux/WSL2, show the apt/dnf/pacman row for the detected $PKG_MGR (omit the other two). Show snap and flatpak rows only when those tools were detected via command -v in Step 5. Omit all three on macOS unless snap or flatpak is installed there via third-party means.

Omit the entire "Windows Packages" group on macOS or plain Linux. In WSL2, omit any row whose tool was not detected by command -v in Step 2.

## Rules

- Never run sudo
- Never auto-reset dirty repos — always ask first
- Never auto-reset non-fast-forward pulls — surface the command for the user
- Each package category has its own confirmation gate — skipping one never skips others
- macOS updates with `[restart]` always get an explicit restart warning before running
