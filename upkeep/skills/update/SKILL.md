---
name: upkeep:update
version: 1.1.0-dev
author: KyleNesium
description: |
  Update AI skills and package managers in one sweep. On macOS, four parallel
  scout agents discover outdated tools, a compatibility synthesizer plans the
  upgrade order with cross-manager risk flags (brew:node ⇒ npm-globals,
  brew:openssl ⇒ ruby native gems, system Ruby ⇒ --user-install), and a
  single approval gate replaces per-category Y/N fatigue. Linux & WSL2 use
  the v1.0 sequential flow. Sub-modes: audit (no changes), skills (git-pull
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
  - Agent
  # Linux system tools
  - Bash(systemctl *)
  - Bash(journalctl *)
  # Linux package managers (Phase 4 of roadmap adds upgrade commands)
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

## Environment Detection

Run this FIRST, before any step. It sets `$OS_TYPE` (macos / linux / wsl2), `$OS_DISTRO`, and `$PKG_MGR` — Step 2 and Step 5 gate `mas` and `softwareupdate` on `$OS_TYPE = "macos"`.

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
   → run the macOS Parallel Flow below (Steps 1m–5m)
   → skip the v1.0 Sequential Flow (Steps 1–6)
else:
   → skip the macOS Parallel Flow
   → run the v1.0 Sequential Flow (Steps 1–6, unchanged for Linux/WSL2)
```

The macOS Parallel Flow uses four scout agents, a synthesizer agent, a single
approval gate, parallel apply for independent ecosystems, and a post-flight
health check. Linux/WSL2 paths are intentionally untouched in v1.1; they will
be ported in v1.1.x.

---

## macOS Parallel Flow — Disk-Space Pre-Flight

Run before any agent fans out:

```bash
FREE_GB=$(df -k / 2>/dev/null | awk 'NR==2 {print int($4/1024/1024)}')
if [ -z "$FREE_GB" ] || [ "$FREE_GB" -lt 5 ]; then
  echo "✗ Refusing to start: only ${FREE_GB:-?} GB free on /. Free up at least 5 GB and re-run."
  exit 1
elif [ "$FREE_GB" -lt 10 ]; then
  echo "⚠ Warning: only ${FREE_GB} GB free on /. Heavy brew formulas (qt, ffmpeg, mlx) can spike disk usage."
fi
```

If refused, stop here. If warned, continue to discovery.

## Step 1m (macOS): Parallel Discovery — Four Scout Agents

Run these four `Agent` calls in a **single tool-use block** so they execute in
parallel. Each scout owns a domain, runs its own bash discovery, and returns a
fragment of the overall JSON. Keep prompts self-contained — scouts don't see
each other's context.

### Discovery JSON schema (`schema_version: "1"`)

The four fragments combine into:

```json
{
  "schema_version": "1",
  "os": {"type": "macos", "arch": "arm64|x86_64"},
  "skills":   { /* skills-scout */ },
  "native":   { /* native-scout */ },
  "language": { /* language-scout */ },
  "shadow":   { /* shadow-scout */ },
  "disk":     {"free_gb": 124, "warn_threshold_gb": 10, "refuse_threshold_gb": 5}
}
```

Detailed per-domain shape: see `.planning/phases/07-parallel-discovery/07-CONTEXT.md`.

### Scout 1 — `skills-scout`

> You are the upkeep skills scout. Discover all updatable AI skills on this
> macOS machine and return a JSON `skills` block per the schema below.
>
> **Cover:**
> 1. Git-cloned skills under `~/.claude/skills/*/.git`. For each: `git fetch
>    --tags -q origin`, count commits behind `origin/<branch>`, read VERSION
>    or plugin.json for current version, list newest 5 commit subjects, scan
>    CHANGELOG.md for `BREAKING\|Breaking` lines between current and target.
> 2. Git-cloned skills under `~/.codex/skills/*/.git` — treat the same way.
> 3. Plugin-cache-managed skills (e.g. upkeep itself when it lives under
>    `~/.claude/plugins/cache/`). Add to `managed[]` with the
>    `/plugin update <name>` command.
> 4. Counts only: `~/.claude/plugins/cache/` total dirs, `~/.codex/skills/*`
>    total dirs.
>
> **Output:** valid JSON only, no prose, no markdown fences. Use this shape:
>
> ```json
> {
>   "git_repos": [{"name": "...", "path": "...", "branch": "main",
>                  "current_version": "...", "commits_behind": 0,
>                  "newest_commit_subjects": [], "breaking_lines": [],
>                  "dirty_files": [], "detached": false, "remote_ok": true,
>                  "manager": "claude" }],
>   "managed": [{"name": "upkeep", "manager": "claude-code-plugin",
>                "version": "1.0.6", "update_command": "/plugin update upkeep"}],
>   "info": {"claude_plugins": 0, "codex_skills_total": 0, "codex_skills_git": 0},
>   "errors": []
> }
> ```

### Scout 2 — `native-scout`

> You are the upkeep native-package scout. Discover outdated brew packages,
> Mac App Store updates, and macOS software updates. Return a JSON `native`
> block per the schema below.
>
> **Cover:**
> 1. Brew: prefer `brew outdated --json=v2 2>/dev/null`; fall back to plain
>    `brew outdated` when JSON is unavailable. For each formula, classify
>    `bump` as `major|minor|patch` from semver delta of `installed_versions`
>    vs `current_version`.
> 2. mas: `mas outdated 2>/dev/null` if `command -v mas` succeeds.
> 3. softwareupdate: `softwareupdate -l 2>&1`. Set `restart_required: true`
>    if the listing contains `[restart]`.
>
> **Output:** valid JSON only.
>
> ```json
> {
>   "brew": {"installed": true, "outdated": [{"name": "node",
>            "from": "20.18.1", "to": "22.10.0", "bump": "major"}]},
>   "mas": {"installed": false, "outdated": []},
>   "softwareupdate": {"installed": true, "updates": [], "restart_required": false},
>   "errors": []
> }
> ```

### Scout 3 — `language-scout`

> You are the upkeep language-ecosystem scout. Discover outdated tools across
> npm/pipx/gems/uv/bun/deno/rustup/cargo/mise. Return a JSON `language` block
> per the schema below.
>
> **Cover (skip silently when not installed):**
> - npm: `npm outdated -g --json 2>/dev/null` parsed into name/from/to/bump
> - pipx: `pipx list --short 2>/dev/null`
> - gems: `gem outdated 2>/dev/null` parsed into name/from/to/bump.
>   Detect system Ruby: set `system_ruby: true` and capture `ruby_version`
>   when `command -v ruby` resolves to `/usr/bin/ruby` AND `ruby --version`
>   starts with `ruby 2.`
> - uv: `uv self version 2>/dev/null`
> - bun: `bun --version 2>/dev/null`
> - deno: `deno --version 2>/dev/null`
> - rustup: `rustup check 2>/dev/null`
> - cargo: `cargo install-update --list 2>/dev/null` (only if cargo-update
>   plugin installed)
> - mise: `mise outdated 2>/dev/null`
>
> **Output:** valid JSON only.
>
> ```json
> {
>   "npm":    {"installed": true, "outdated": []},
>   "pipx":   {"installed": true, "tools": [], "outdated_count": 0},
>   "gems":   {"installed": true, "system_ruby": true, "ruby_version": "2.6", "outdated": []},
>   "uv":     {"installed": true, "current": "0.9.7"},
>   "bun":    {"installed": true, "current": "1.3.9"},
>   "deno":   {"installed": false},
>   "rustup": {"installed": false},
>   "cargo":  {"installed": false},
>   "mise":   {"installed": false},
>   "errors": []
> }
> ```

### Scout 4 — `shadow-scout`

> You are the upkeep PATH-shadow scout. Detect shadowed binaries and broken
> symlinks under brew prefixes. Return a JSON `shadow` block.
>
> **Method:**
> 1. `brew --prefix` to find the brew root (typically `/opt/homebrew` on
>    Apple Silicon, `/usr/local` on Intel).
> 2. List binaries from `${PREFIX}/bin`. For each binary, run
>    `which -a <binary>`. If multiple paths and the brew path is not first,
>    record a duplicate.
> 3. `find -L ${PREFIX}/bin -maxdepth 1 -type l ! -exec test -e {} \; -print`
>    for broken symlinks (cap output at 10).
>
> **Output:** valid JSON only.
>
> ```json
> {
>   "duplicates": [{"binary": "gemini",
>                   "primary": "/Users/kyle/.superset/bin/gemini",
>                   "shadowed": ["/opt/homebrew/bin/gemini"]}],
>   "broken_symlinks": [],
>   "errors": []
> }
> ```

### Combine fragments

After all four scouts complete, assemble the combined JSON document inline
(no disk write). Pass it as input to the synthesizer agent in Step 2m.

If any scout returns invalid JSON or an `errors[]` entry, surface the error
in the final report under `Manual steps` and continue with a partial
discovery — don't block the run.

## Step 2m (macOS): Synthesize Plan — Compatibility Synthesizer Agent

Single sequential `Agent` call. Inputs: combined discovery JSON + the contents
of `compatibility.json` (read with `Read`). Output: ordered plan JSON.

### Pre-call: load history file for ETA self-tuning

Before invoking the synthesizer, read the history file into a shell
variable so it can be injected into the prompt. If absent, use `{}`.

```bash
HIST_FILE="$HOME/.claude/data/upkeep-history.json"
if [ -f "$HIST_FILE" ]; then
  HISTORY_JSON=$(cat "$HIST_FILE")
else
  HISTORY_JSON='{}'
fi
```

### Synthesizer prompt

> You are the upkeep compatibility synthesizer. Read the discovery JSON and
> compatibility matrix below, then emit a single JSON `plan` document per the
> schema. **Emit JSON only — no prose, no markdown fences.**
>
> **Hard rules:**
> 1. Only reference downstream effects that appear in `compatibility.json` —
>    do not invent edges. For each materialised edge, read
>    `severity_on_major` and `severity_on_minor` and copy the matching
>    value into the warning entry as `severity`. Sort `plan.warnings[]`
>    by severity: `high` first, then `medium`, then `low`.
> 2. Classify version delta as `major` / `minor` / `patch` strictly by
>    semver: same-major-different-minor → minor; same-minor-different-patch
>    → patch; otherwise major.
> 3. If `language.gems.system_ruby` is `true`, set
>    `tool_specs.gems.command` to `gem update --user-install` and add
>    `rationale_for_flag: "system Ruby ${ruby_version} detected; --user-install avoids sudo"`.
> 4. If `disk.free_gb < 5`, set
>    `warnings: [{"severity": "high", "message": "Refusing to run: only ${free_gb} GB free"}]`
>    and emit empty `ordered_groups`.
> 5. Build `ordered_groups` in this order: `skills` → `brew` → `language`
>    (parallelism: parallel) → `stores` (mas, macOS).
> 6. ETA heuristic: if `~/.claude/data/upkeep-history.json` is provided in
>    your input, use the median of the last 5 runs per category. Otherwise
>    use the bake-in defaults below.
> 7. Output `manual_steps` for: plugin-cache-managed skills (surface
>    `/plugin update <name>`), PATH shadows, codex skills without `.git`.
> 8. If `native.softwareupdate.restart_required` is `true`, include a
>    `macos` entry under `tool_specs` with
>    `{kind: "store", command: "softwareupdate -ia", restart_required: true, preconditions: []}`
>    and ensure the `stores` `ordered_groups` entry lists `macos`. The
>    `restart_required` field gates Step 3m's separate restart-warning
>    `AskUserQuestion`.
>
> **Bake-in ETA defaults (seconds per item):**
> - brew: 25, npm: 30, pipx: 20, gems: 15, uv: 5 total, bun: 5 total,
>   skills: 3, mas: 30, macOS: 300.
>
> Convert seconds → minutes when emitting `summary.eta_minutes_p50` /
> `eta_minutes_p90`. Use `ceil(total_seconds / 60)` so an 89-second
> estimate rounds to 2 minutes, not 1.
>
> **Input:**
> Discovery JSON:
> ```json
> {{ paste combined discovery JSON here }}
> ```
> Compatibility matrix:
> ```json
> {{ paste contents of compatibility.json here }}
> ```
> History (may be empty):
> ```json
> ${HISTORY_JSON}
> ```

### Plan output schema

See `.planning/phases/08-compatibility-synthesizer/08-CONTEXT.md` for the
full shape. Required fields: `plan.summary`, `plan.warnings`,
`plan.manual_steps`, `plan.ordered_groups[]`, `plan.tool_specs{}`.

### Synthesizer fallback

If the synthesizer Agent call fails (timeout, schema-invalid output), build a
fallback plan inline:

- Order: `skills` → `brew` → each language tool serially → `mas` → `macOS`
- No compatibility flags, no ETA
- Surface in the report: `compatibility analysis unavailable — running in fallback mode`

## Step 3m (macOS): Approve & Apply

### Schema gate (check first)

Reject plans with the wrong `schema_version` and route to the fallback
plan instead. Skipped silently when `jq` is not installed (matches the
graceful degradation in Step 5m's history writer).

```bash
if command -v jq >/dev/null 2>&1; then
  if ! jq -e '.schema_version == "1"' <<<"$PLAN_JSON" >/dev/null 2>&1; then
    echo "compatibility analysis unavailable — running in fallback mode"
    PLAN_JSON="$FALLBACK_PLAN_JSON"
  fi
fi
```

`$FALLBACK_PLAN_JSON` is the rule-based plan from `### Synthesizer fallback`
above. The string `compatibility analysis unavailable — running in fallback mode`
is reused verbatim — do not introduce a new variant.

### Audit-mode short-circuit (check first)

If sub-mode is `audit`, render the plan from Step 2m as the report and
**stop here** — skip the approval gate, apply, post-flight, and history
write entirely.

### Single approval gate

Render the plan compactly:

```
Plan:
  Skills (N):     <name> <from> → <to> (<bump>)
  brew  (N):      ⚠ major: <names>  | minor: <count> | patch: <count>
  npm   (N):      <names>
  pipx  (N):      <names>
  gems  (N):      <major bumps>     [--user-install: system Ruby X detected]
  uv    (self):   <from> → latest
  bun   (self):   <from> → latest
  mas   (N):      <names>
  macOS (N):      <updates>          [restart] if applicable

Risks flagged:
  • <one line per plan.warnings entry, plus downstream-effect callouts>

Manual steps (after apply):
  • <one line per plan.manual_steps entry>

ETA: ~<p50> minutes (p50), up to <p90> minutes (p90)
Disk free: <free_gb> GB <✓ or ⚠>
```

Single `AskUserQuestion`:
- A) Apply all
- B) Drop categories
- C) Cancel

If "Drop categories", emit a second multi-select `AskUserQuestion` with one
option per category in the plan.

### Apply orchestration

Set up race-free accumulators for upgraded names. These feed Step 4m's
PATH-shadow and resolution-recheck loops:

```bash
UPGRADED_FORMULAS_FILE=$(mktemp)
UPGRADED_TOOLS_FILE=$(mktemp)
trap "rm -f $UPGRADED_FORMULAS_FILE $UPGRADED_TOOLS_FILE" EXIT
```

Iterate `plan.ordered_groups`:

- `parallelism: serial` → run each tool's command in order
- `parallelism: exclusive` → single command, await
- `parallelism: parallel` → fan out via `Bash` `run_in_background`, cap 4
  concurrent, await all via Monitor or `wait`

Each tool command:
1. Run `tool_specs[tool].preconditions` first (e.g., `brew update >/dev/null`)
2. Capture wall time with `time` or `$SECONDS` deltas
3. Wrap with isolation:
   ```bash
   if eval "$CMD" >>"$LOG" 2>&1; then
     RESULT="ok"
     case "$TOOL" in
       brew)
         # Append every formula brew upgraded this run
         grep -E "^==> Upgrading" "$LOG" | awk '{print $3}' | cut -d/ -f1 \
           >> "$UPGRADED_FORMULAS_FILE"
         ;;
       *)
         echo "$TOOL" >> "$UPGRADED_TOOLS_FILE"
         ;;
     esac
   else
     RESULT="fail:$?"
   fi
   ```
4. Pipe stdout through deprecation collector:
   `tee -a "$DEPRECATION_LOG" >/dev/null` for any line matching
   `(deprecated|deprecation|warning|WARN)`

After all groups complete, populate the env vars Step 4m consumes:

```bash
UPGRADED_FORMULAS=$(sort -u "$UPGRADED_FORMULAS_FILE" | tr '\n' ' ')
UPGRADED_TOOLS=$(sort -u "$UPGRADED_TOOLS_FILE" | tr '\n' ' ')
export UPGRADED_FORMULAS UPGRADED_TOOLS
```

A failure in one tool **never blocks others** in the same or later groups.

### macOS update restart warning

If `plan.tool_specs.macos.restart_required` is `true`, before running:

> ⚠ This update requires a restart. Save your work.
> Apply? A) Yes  B) Skip macOS updates

This is a separate `AskUserQuestion` even when "Apply all" was chosen earlier.

## Step 4m (macOS): Post-Flight

Always runs after apply (even on partial failure). Skipped in audit mode.

```bash
# 1. brew doctor noise filter
DOCTOR_OUT=$(brew doctor 2>&1)
case "$DOCTOR_OUT" in
  *"Your system is ready to brew."*) ;;  # silent on clean
  *) echo "── brew doctor ──"; echo "$DOCTOR_OUT" ;;
esac

# 2. PATH shadow re-check, scoped to upgraded brew formulas
for FORMULA in $UPGRADED_FORMULAS; do
  for BIN in $(brew list "$FORMULA" 2>/dev/null | grep "/bin/" | xargs -n1 basename | sort -u); do
    PATHS=$(which -a "$BIN" 2>/dev/null | sort -u)
    COUNT=$(echo "$PATHS" | wc -l | tr -d ' ')
    if [ "$COUNT" -gt 1 ]; then
      FIRST=$(echo "$PATHS" | head -1)
      BREW_PATH="$(brew --prefix)/bin/$BIN"
      if [ "$FIRST" != "$BREW_PATH" ]; then
        echo "shadow: $BIN — first match $FIRST (brew path: $BREW_PATH)"
      fi
    fi
  done
done

# 3. Resolution re-check for every upgraded tool name
for TOOL in $UPGRADED_TOOLS; do
  command -v "$TOOL" >/dev/null 2>&1 || echo "⚠ $TOOL no longer resolves on PATH"
done

# 4. Deprecation aggregator
if [ -s "$DEPRECATION_LOG" ]; then
  echo "── Deprecation warnings ──"
  sort -u "$DEPRECATION_LOG" | head -20
fi
```

## Step 5m (macOS): Report

```
── ⚠ Risks observed ────────────────────────────────────
  • <one line per surfaced cross-manager risk that materialised>
  • <e.g. "brew:openssl 3.3 → 3.4 — re-test gems w/ native ext">

── Manual steps ────────────────────────────────────────
  • <one line per plan.manual_steps entry, plus PATH shadows from post-flight>

── Update Report ───────────────────────────────────────
  upkeep   ⓘ /plugin update upkeep
  gstack   ✓ updated     1.5.1.0 → 1.27.1.0
  brew     ✓ upgraded    36 packages
  npm      ✓ upgraded    11.12.1 → 11.14.0
  pipx     ✓ upgraded    1 tool   (semgrep 1.159.0 → 1.161.0)
  gems     ✓ upgraded    ~48 gems (--user-install)
  uv       ✓ upgraded    0.9.7 → 0.11.11
  bun      ✓ upgraded    1.3.9 → 1.3.13
  mas      —             not installed
  macOS    ✓ none

── Informational ───────────────────────────────────────
  Claude plugins  10 (managed by Claude Code)
  Codex skills    16 (4 git-managed → updated; 12 manual)
```

### History write

```bash
HIST_DIR="$HOME/.claude/data"
HIST_FILE="$HIST_DIR/upkeep-history.json"
mkdir -p "$HIST_DIR" 2>/dev/null

if command -v jq >/dev/null 2>&1; then
  ENTRY=$(jq -n --arg ts "$(date -u +%FT%TZ)" \
    --argjson minutes "$MINUTES_JSON" \
    '{ts: $ts, minutes: $minutes}')
  if [ -f "$HIST_FILE" ]; then
    jq --argjson entry "$ENTRY" '.runs += [$entry]' "$HIST_FILE" > "$HIST_FILE.tmp" \
      && mv "$HIST_FILE.tmp" "$HIST_FILE"
  else
    jq -n --argjson entry "$ENTRY" '{schema_version:"1", runs:[$entry]}' > "$HIST_FILE"
  fi
else
  echo "ⓘ Install jq to enable ETA self-tuning across runs"
fi
```

History is read by Step 2m on the next invocation to refine the ETA.

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
