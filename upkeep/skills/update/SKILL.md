---
name: upkeep:update
version: 1.6.0
author: KyleNesium
description: |
  Update AI skills and package managers in one sweep. The v1.6 fast path
  collapses discovery, plan synthesis, apply orchestration, post-flight
  checks, and failure diagnosis into one shell script
  (`scripts/update.sh`) on macOS, Linux, AND WSL2. The skill is a thin
  two-turn wrapper: turn 1 builds the plan and renders the approval gate;
  turn 2 runs apply and renders the report. brew metadata is TTL-cached
  (1h default) so warm runs hit the gate in <5s. The failure-diagnoser
  LLM agent from v1.3 is now a deterministic pattern table
  (`scripts/diagnose.sh`) covering macOS and Linux failures. On Linux,
  user-scoped managers (language tools, snap, flatpak) are auto-applied;
  apt/dnf/pacman upgrades are surfaced as manual sudo steps (never run —
  upkeep never uses sudo). On WSL2, Windows package managers are
  audit-only. Enrichment (changelog summaries + project impact) is opt-in
  behind `--advisor`. Sub-modes: audit (no changes), skills (git-pull
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
  - Bash(apt-get *)
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

You are a cross-platform update specialist (macOS, Linux, WSL2). Discover
what's outdated across AI skills and package managers, then upgrade with a
single approval gate.

### Hard Rule: plan and apply are separate turns

The fast path is exactly two LLM turns on every platform:

1. **Plan turn:** run `update.sh plan <mode>`, render the gate, end the
   turn at the `AskUserQuestion`.
2. **Apply turn:** on approval, run `update.sh apply <plan-file>`, render
   the report.

Never print "Apply?" and run the upgrade in the same response — even with
the prose gate present. Audit mode never reaches an apply step.

`update.sh` is OS-aware: it auto-detects macOS / Linux / WSL2 and builds
the matching plan. The same two-turn contract holds regardless of OS.

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

`update.sh` detects the OS itself (and emits `os.type` in the plan JSON), so
you do not need to run detection before invoking it. This block is optional —
run it only when you want to announce the environment or show the WSL2 banner
before the plan. It sets `$OS_TYPE` (macos / linux / wsl2), `$OS_DISTRO`, and
`$PKG_MGR`.

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

As of v1.6 there is **one path for all platforms** — the Fast Path below
(Turn 1 + Turn 2). `update.sh` branches internally on the detected OS:

```
macos → brew / mas / softwareupdate + language tools + skills
linux → snap / flatpak + language tools + skills;
        apt|dnf|pacman surfaced as MANUAL sudo steps (never auto-run)
wsl2  → same as linux + Windows package managers shown audit-only
```

The legacy v1.0 sequential flow (per-category gates) was retired in v1.6;
all platforms now get the single-gate UX. If `$OS_TYPE` is `unknown`, report
"Update skill requires macOS, Linux, or WSL2." and stop.

---

## Fast Path (v1.6 — all platforms)

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

- If `manual_steps[]` contains a `system-sudo` entry (Linux: apt/dnf/pacman
  has pending upgrades that upkeep can't auto-apply), do **not** say
  "everything is up to date" — that would be wrong. Instead render:
  `Nothing to auto-apply, but N system package(s) need a manual upgrade:`
  then the literal `sudo …` command from that step, plus any other
  `manual_steps[]`. Stop.
- Otherwise render `Everything is up to date.`, surface any remaining
  `manual_steps[]` as informational, and stop.

#### D. Approval gate render

Otherwise render the plan as the gate. Show only the rows whose
`summary.category_counts` value is non-zero. macOS surfaces brew / mas /
macOS rows; Linux/WSL2 surface snap / flatpak / system rows. Language and
skills rows are shared.

```
Plan:
  Skills (N):     <git_repos applied> (from manual_steps for dirty/untrusted)
  # macOS native
  brew  (N):      ⚠ major: <names> | minor: <count> | patch: <count>
  mas   (N):      <names>
  macOS (N):      <updates>          [restart] if restart_required=true
  # Linux/WSL2 native (auto-applied — user-scoped, no sudo)
  snap  (N):      <names>
  flatpak (N):    <names>
  # Shared language managers
  npm   (N):      <names>
  pipx  (N):      <names>
  gems  (N):      <major bumps>     [--user-install: gems_user_install=true]
  uv    (self):   <from> → latest
  bun   (self):   <from> → latest

Risks flagged:
  • <one line per warnings[] entry, severity-ordered>

Manual steps (you run these — NOT auto-applied):
  • <one line per manual_steps[] entry>
  • system-sudo entries are apt/dnf/pacman upgrades: show the literal
    `sudo …` command verbatim. upkeep NEVER runs sudo.
  • windows-audit entries (WSL2): show the PowerShell guidance verbatim.

ETA: ~<summary.eta_minutes_p50>m (p50), up to <eta_minutes_p90>m (p90)
Disk free: <summary.disk_free_gb> GB
```

On Linux/WSL2 the `system-sudo` manual step(s) are the apt/dnf/pacman
upgrades. They are intentionally NOT in `ordered_groups` and NOT applied by
Turn 2 — render them prominently so the user knows to run them in their own
shell. WSL2 Windows package managers appear as a `windows-audit` manual
step (never executed).

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
  snap     <symbol> <result>                (Linux — from .upgraded_tools)
  flatpak  <symbol> <result>                (Linux — from .upgraded_tools)

── Manual (run yourself) ───────────────────────────────  (Linux/WSL2, if any)
  • <system-sudo command(s) from the plan's manual_steps — apt/dnf/pacman>
  • <windows-audit guidance on WSL2>

── Post-flight ─────────────────────────────────────────
  • brew doctor: <.doctor or "clean">    (macOS only)
  • PATH shadows: <.shadow_hits[] or "none">
  • Resolution failures: <.resolution_failures[] or "none">
```

Only show rows present for the platform: `snap`/`flatpak` on Linux/WSL2;
`brew`/`mas`/`macOS`/brew-doctor/PATH-shadows on macOS. The `Manual (run
yourself)` block restates the system-sudo / windows-audit steps so the user
has the exact commands after the auto-applied work finishes.

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
  gems uv bun mas macos snap flatpak` before any dispatcher call.
  apt/dnf/pacman are **deliberately not** in the allowlist — they require
  root, so the dispatcher rejects them and the synthesizer surfaces them as
  manual sudo steps instead (upkeep never runs sudo).
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
| `UPKEEP_OS_OVERRIDE` | unset | Test seam — force `os.type` (`macos`/`linux`/`wsl2`); short-circuits `uname` |
| `UPKEEP_PKG_MGR_OVERRIDE` | unset | Test seam — force `$PKG_MGR` (`apt`/`dnf`/`pacman`) |

---

## Legacy v1.0 sequential flow — retired in v1.6

The per-category sequential flow (old Steps 1–6) that Linux/WSL2 used
through v1.5 has been removed. All platforms now use the single-shot Fast
Path above (`update.sh plan|apply`). The behaviour it encoded is preserved:
system packages (apt/dnf/pacman) are surfaced as manual sudo steps,
snap/flatpak are auto-applied, and WSL2 Windows package managers are
audit-only — now driven by `discover.sh` + `synthesize.sh` instead of prose.

## Rules

- Never run sudo — apt/dnf/pacman upgrades are surfaced as manual steps, never executed
- Never auto-reset dirty repos — always ask first
- Never auto-reset non-fast-forward pulls — surface the command for the user
- One approval gate covers the whole plan; "Drop categories" lets the user exclude tools before apply
- macOS updates with `[restart]` always get an explicit restart warning before running
- The `$ <command>` lines in diagnosis fix-options and the manual sudo steps are text only — never auto-executed
