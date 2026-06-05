#!/usr/bin/env bash
# upkeep update orchestrator — single-shot (v1.5)
#
# Collapses what v1.4 did across five SKILL.md steps (1m discover, 2m
# synthesize, 2.5m enrich, 3m apply, 4m post-flight, 4.5m diagnose,
# 5m report) into two shell invocations:
#
#   update.sh plan <mode> [--no-cache]
#     → builds plan, writes it to a temp file, prints SKILL.md-facing
#       summary JSON on stdout (plan_file path, render hints, gate
#       requirements). Total LLM exposure: one turn to render the gate.
#
#   update.sh apply <plan-file> [--drop=tool1,tool2] [--advisor]
#     → reads the plan, runs the apply dispatcher + post-flight +
#       pattern-table diagnoser + history write, prints SKILL.md-facing
#       report JSON on stdout. Total LLM exposure: one turn to render
#       the report.
#
# All v1.4 security invariants preserved:
#   - hardcoded dispatcher allowlist (no eval of synthesizer output)
#   - tool_specs.command / preconditions ignored if present
#   - discovery sanitization (256-char string cap + free-text denylist)
#   - trust-on-first-use surfaced as untrusted_repos in plan JSON

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="${UPKEEP_DATA_DIR:-$HOME/.claude/data}"
# v1.7: canonical root the plugin marketplace git-pull is fenced to. The
# apply phase refuses any marketplace_path that doesn't resolve under it
# (mirrors the skills-root containment check). Test seam overrides it.
MARKETPLACES_ROOT="${UPKEEP_PLUGIN_MARKETPLACES:-$HOME/.claude/plugins/marketplaces}"

# ── Common helpers ───────────────────────────────────────────────
_require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    # v1.5.1: emit JSON to stdout (SKILL.md reads `.error`); prose
    # diagnostic to stderr. Without this, SKILL.md would see empty
    # stdout and have no programmatic way to surface the failure.
    printf '%s\n' '{"error":"jq required but not found"}'
    echo "update.sh: jq is required" >&2
    exit 1
  fi
}

_die() {
  jq -n --arg msg "$1" '{error:$msg}'
  exit 1
}

# ───────────────────────────────────────────────────────────────────
# COMMAND: plan
# ───────────────────────────────────────────────────────────────────
_cmd_plan() {
  local mode="${1:-all}"
  shift || true
  local no_cache=0 fresh=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-cache) no_cache=1 ;;
      --fresh)    fresh=1 ;;
      *) ;;
    esac
    shift
  done

  _require_jq

  # Run discovery. --no-cache bypasses the brew-update TTL cache; --fresh
  # git-fetches plugin marketplaces so outdated detection compares against
  # the upstream manifest rather than the local clone. Both default off;
  # passing 0 is inert (discover.sh treats only "1" as enabled).
  local discovery
  discovery=$(UPKEEP_NO_CACHE="$no_cache" UPKEEP_FRESH_MARKETPLACES="$fresh" \
    bash "$SCRIPT_DIR/discover.sh" 2>/dev/null) \
    || _die "discover.sh failed"

  if ! jq -e '.schema_version == "1"' <<<"$discovery" >/dev/null 2>&1; then
    _die "discover.sh produced invalid JSON"
  fi

  # Apply mode filter — audit and skills modes shrink the synthesizer's
  # input so the plan reflects what the user actually asked for.
  case "$mode" in
    skills)
      # Replace native + language with empty stubs so the synthesizer
      # emits only the skills group. Going field-by-field misses things
      # like pipx.outdated_count (a number, not an array) and tools[].
      # The stub schema matches what the scouts emit when nothing is
      # installed.
      #
      # v1.6 (F1): the native stub must match the discovery's OS shape, not
      # always macOS. The synthesizer's `// []` defenses would absorb a
      # shape mismatch today, but an OS-matched stub keeps the plan file
      # honest and future-proof against synthesizer changes that read keys
      # directly. The language stub is OS-agnostic (shared verbatim).
      local _os_type
      _os_type=$(jq -r '.os.type // "macos"' <<<"$discovery")
      local _native_stub
      case "$_os_type" in
        linux|wsl2)
          _native_stub='{
            system: {manager:"unknown", installed:false, upgradable:[], count:0, requires_sudo:true},
            snap:   {installed:false, refreshable:[]},
            flatpak:{installed:false, updatable:[]},
            windows:{wsl2:false, mnt_c:false, managers:[]},
            errors: []
          }'
          ;;
        *)
          _native_stub='{
            brew: {installed:false, outdated:[]},
            mas:  {installed:false, outdated:[]},
            softwareupdate: {installed:false, updates:[], restart_required:false},
            errors: []
          }'
          ;;
      esac
      discovery=$(jq --argjson native "$_native_stub" '
        .native = $native
        | .language = {
          npm: {installed:false, outdated:[]},
          pipx: {installed:false, tools:[], outdated_count:0},
          gems: {installed:false, system_ruby:false, outdated:[]},
          uv: {installed:false},
          bun: {installed:false},
          deno: {installed:false},
          rustup: {installed:false},
          cargo: {installed:false},
          mise: {installed:false},
          errors: []
        }
      ' <<<"$discovery")
      ;;
    packages)
      discovery=$(jq '.skills.git_repos=[] | .skills.managed=[]' <<<"$discovery")
      ;;
    audit|all|"")
      mode="${mode:-all}"
      ;;
    *)
      _die "unknown mode: $mode (expected: audit|skills|packages|all)"
      ;;
  esac

  # Run synthesizer
  local hist_file="$DATA_DIR/upkeep-history.json"
  local plan
  plan=$(bash "$SCRIPT_DIR/synthesize.sh" \
    "$SKILL_DIR/compatibility.json" \
    "$hist_file" \
    <<<"$discovery" 2>/dev/null) || _die "synthesize.sh failed"

  if ! jq -e '.schema_version == "1"' <<<"$plan" >/dev/null 2>&1; then
    _die "synthesize.sh produced invalid plan JSON"
  fi

  # Extract untrusted repos (the v1.3+ trust gate operates on these).
  # v1.5.1 (codex P2 round 2): these values come from
  # `git config --get remote.origin.url` and filesystem paths, so they
  # SHOULD be ASCII URL/path characters. Defensively:
  #
  #   1. Strip control bytes (incl. ANSI escapes) so the LLM-rendered
  #      gate cannot contain terminal control sequences.
  #   2. Disarm common shell-metachar prompt-injection vectors:
  #      backticks, `$(`, `${`, backslash. These have no legitimate
  #      place in a git remote URL or POSIX repo path and are common
  #      injection tokens.
  #   3. Clamp to 256 chars.
  #
  # Honest scope: this defends the gate against the obvious classes
  # (terminal escapes, naive `$(rm ...)`, `` `pwd` ``). It does NOT and
  # cannot fully defend against printable-text prompt injection —
  # nothing regex-based can. The trust gate exists precisely so the
  # user reviews the URL before any fetch.
  local untrusted
  untrusted=$(jq -c '
    [ .skills.git_repos[]?
      | select(.untrusted == true)
      | {name, path, remote_url}
      | with_entries(
          .value |= (
            tostring
            | gsub("[[:cntrl:]]"; "")
            | gsub("`"; "")
            | gsub("\\$\\("; "$_(")
            | gsub("\\$\\{"; "${_")
            | gsub("\\\\"; "")
            | .[0:256]
            | if length == 0 then "<scrubbed>" else . end
          )
        )
    ]
  ' <<<"$discovery")

  # Stash full plan + discovery snapshot to disk so apply can read
  # them without re-running discovery (which would now show post-apply
  # state, not the state the user approved against).
  mkdir -p "$DATA_DIR" 2>/dev/null
  chmod 700 "$DATA_DIR" 2>/dev/null
  # Sweep stale plan files (>24h) so the data dir doesn't grow unbounded
  # when users invoke /upkeep:update repeatedly without applying.
  find "$DATA_DIR" -maxdepth 1 -name 'upkeep-plan.*' -mmin +1440 -delete 2>/dev/null
  local plan_file plan_workdir plan_suffix
  # v1.5.1: TOCTOU-safe plan write (codex P1).
  # Prior version: `mktemp` then `> "$plan_file"` reopened the file by path,
  # giving a same-user attacker a window to swap it for a symlink and have
  # jq clobber an arbitrary target.
  # Fix: write inside a 0700 mktemp -d (which other UIDs cannot enter and
  # only this process knows the suffix of), then atomic-rename via mv —
  # rename(2) does not follow symlinks at destination, so a swapped-in
  # symlink gets replaced rather than written through.
  plan_workdir=$(mktemp -d "${DATA_DIR}/.upkeep-tmp.XXXXXX") || _die "mktemp -d failed"
  chmod 700 "$plan_workdir" 2>/dev/null
  plan_suffix=${plan_workdir##*.}
  plan_file="${DATA_DIR}/upkeep-plan.${plan_suffix}"
  jq -n --argjson plan "$plan" --argjson discovery "$discovery" \
    --arg mode "$mode" --arg ts "$(date -u +%FT%TZ)" \
    '{schema_version:"1", mode:$mode, created_at:$ts,
      plan:$plan, discovery:$discovery}' > "$plan_workdir/plan.json" \
    || { rm -rf -- "$plan_workdir"; _die "plan JSON write failed"; }
  mv -- "$plan_workdir/plan.json" "$plan_file" \
    || { rm -rf -- "$plan_workdir"; _die "plan rename failed"; }
  rmdir -- "$plan_workdir" 2>/dev/null

  # Audit-mode short-circuit: no gate, no apply, plan is the report.
  local needs_approval=true
  if [ "$mode" = "audit" ]; then
    needs_approval=false
  fi

  # If plan has empty ordered_groups (nothing to do), no gate either.
  local group_count
  group_count=$(jq '.ordered_groups | length' <<<"$plan")
  if [ "$group_count" = "0" ]; then
    needs_approval=false
  fi

  # SKILL.md-facing summary. Compact — render hints, not full plan.
  # v1.5.1 (codex P2): every string in the emitted JSON is run through
  # one final sanitization pass — strip control bytes (incl. ANSI
  # escapes) and clamp to 256 chars — so SKILL.md never has to render
  # raw discovery-derived bytes carrying terminal control sequences.
  # Numbers and booleans are untouched.
  #
  # Shell-metachar / prompt-injection disarming for upstream-controlled
  # fields (remote URLs, repo paths, repo names) happens earlier in the
  # `untrusted` extraction above — the broader `walk` here ONLY does
  # control-byte stripping + length clamping, since fields like
  # `summary.eta_minutes_p50` or `ordered_groups[].name` are
  # synthesizer-controlled and don't need shell-metachar scrubbing.
  jq -n \
    --arg plan_file "$plan_file" \
    --argjson plan "$plan" \
    --argjson untrusted "$untrusted" \
    --argjson needs_approval "$needs_approval" \
    --arg mode "$mode" \
    '{
      mode: $mode,
      plan_file: $plan_file,
      needs_approval: $needs_approval,
      summary: $plan.summary,
      warnings: $plan.warnings,
      manual_steps: $plan.manual_steps,
      ordered_groups: $plan.ordered_groups,
      risk_categories: ($plan.risk_categories // []),
      restart_required: ($plan.tool_specs.macos.restart_required // false),
      gems_user_install: ($plan.tool_specs.gems.user_install // false),
      untrusted_repos: $untrusted
    }
    | walk(
        if type == "string"
        then (gsub("[[:cntrl:]]"; "") | .[0:256])
        else .
        end
      )'
}

# ───────────────────────────────────────────────────────────────────
# COMMAND: apply
# ───────────────────────────────────────────────────────────────────
_cmd_apply() {
  local plan_file="${1:-}"
  shift || true
  [ -f "$plan_file" ] || _die "plan file not found: $plan_file"

  local drop_csv=""
  local advisor=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --drop=*) drop_csv="${1#--drop=}" ;;
      --advisor) advisor=1 ;;
      *) ;;
    esac
    shift
  done

  _require_jq

  local plan discovery mode
  plan=$(jq -c '.plan' "$plan_file")
  discovery=$(jq -c '.discovery' "$plan_file")
  mode=$(jq -r '.mode' "$plan_file")

  # ── Set up race-free accumulators (matches v1.4 Step 3m) ─────
  # v1.5.1: trap variables are script-scoped (not local) so the EXIT
  # trap can still resolve them after the function returns. With
  # `set -u` enabled, a local-scoped trap target becomes "unbound
  # variable" at trap-fire time, which masks the real error.
  TMP_ROOT_APPLY=$(mktemp -d) || _die "mktemp -d failed"
  local upgraded_formulas_file="$TMP_ROOT_APPLY/upgraded_formulas"
  local upgraded_tools_file="$TMP_ROOT_APPLY/upgraded_tools"
  local plugins_refreshed_file="$TMP_ROOT_APPLY/plugins_refreshed"
  local failure_log_file="$TMP_ROOT_APPLY/failure_log"
  local deprecation_log="$TMP_ROOT_APPLY/deprecation_log"
  local apply_log_root="$TMP_ROOT_APPLY/logs"
  mkdir -p "$apply_log_root"
  trap 'rm -rf -- "${TMP_ROOT_APPLY:-/dev/null/_unset}"' EXIT

  touch "$upgraded_formulas_file" "$upgraded_tools_file" \
        "$plugins_refreshed_file" "$failure_log_file" "$deprecation_log"

  # ── Dropped tools set (from gate's "drop categories" path) ───
  # v1.5.1: bash 3.2 (macOS default) has no associative arrays. Encode
  # the dropped set as a comma-delimited string with sentinel commas at
  # both ends, then check membership via case-pattern match. Same
  # allowlist semantics as the v1.5.0 `local -A` version but works on
  # /bin/bash.
  #
  # codex P2: parse CSV without word-splitting + pathname expansion.
  # Prior version used `for t in $drop_csv` which globbed against cwd.
  local dropped=","
  if [ -n "$drop_csv" ]; then
    local _saved_ifs="$IFS"
    IFS=','
    # `read -r -a` is bash 2.0+; it splits on $IFS, no globbing.
    local _drop_arr=()
    read -r -a _drop_arr <<<"$drop_csv"
    IFS="$_saved_ifs"
    for t in "${_drop_arr[@]}"; do
      case "$t" in
        skills|plugins|brew|npm|pipx|gems|uv|bun|mas|macos|snap|flatpak) dropped="${dropped}${t}," ;;
        *) ;;  # silently ignore unknown tool ids
      esac
    done
  fi
  # Membership helper: returns 0 if the tool is in the dropped set.
  _is_dropped() {
    case "$dropped" in
      *",$1,"*) return 0 ;;
      *) return 1 ;;
    esac
  }

  # ── Validate tool ids against hardcoded allowlist ────────────
  # v1.6: snap + flatpak join the allowlist (user-scoped, no sudo).
  # apt/dnf/pacman are DELIBERATELY absent — they require root and are
  # surfaced as manual_steps by the synthesizer; this _die is the hard
  # guarantee that a malformed plan can never smuggle a sudo manager into
  # the dispatcher.
  local allowed="skills plugins brew npm pipx gems uv bun mas macos snap flatpak"
  local tool
  while read -r tool; do
    [ -z "$tool" ] && continue
    case " $allowed " in
      *" $tool "*) ;;
      *)
        _die "refusing unknown tool id from plan: $tool"
        ;;
    esac
  done < <(jq -r '.ordered_groups[].tools[]' <<<"$plan")

  # ────────────────────────────────────────────────────────────
  # SKILLS APPLY PHASE (runs before dispatcher)
  # ────────────────────────────────────────────────────────────
  local skills_log="$apply_log_root/skills.log"
  : > "$skills_log"
  local skills_applied=0 skills_skipped=0
  while read -r repo_json; do
    [ -z "$repo_json" ] && continue
    local repo_path branch repo_name current_version commits_behind untrusted
    repo_path=$(jq -r '.path' <<<"$repo_json")
    branch=$(jq -r '.branch' <<<"$repo_json")
    repo_name=$(jq -r '.name' <<<"$repo_json")
    current_version=$(jq -r '.current_version // "?"' <<<"$repo_json")
    commits_behind=$(jq -r '.commits_behind // 0' <<<"$repo_json")
    untrusted=$(jq -r '.untrusted // false' <<<"$repo_json")

    [ "$untrusted" = "true" ] && { skills_skipped=$((skills_skipped+1)); continue; }
    [ "$commits_behind" = "0" ] && continue

    # v1.5.1: canonical-path containment check. The prior version used a
    # string-prefix `case` which accepted `.../skills/../outside` and
    # followed symlinks under the skill roots (codex P1).
    #
    # Resolve $repo_path to a canonical absolute path that follows symlinks,
    # then verify it's a subpath of one of the two allowed canonical roots.
    # Trailing-slash discipline on the roots prevents false matches like
    # `~/.codex/skills-evil/` claiming to be under `~/.codex/skills/`.
    _resolved_repo=$(cd -P -- "$repo_path" 2>/dev/null && pwd -P)
    _claude_root=$(cd -P -- "$HOME/.claude/skills" 2>/dev/null && pwd -P)
    _codex_root=$(cd -P -- "$HOME/.codex/skills" 2>/dev/null && pwd -P)
    _path_ok=0
    if [ -n "$_resolved_repo" ]; then
      for _root in "$_claude_root" "$_codex_root"; do
        [ -z "$_root" ] && continue
        case "$_resolved_repo/" in
          "$_root/"*) _path_ok=1; break ;;
        esac
      done
    fi
    if [ "$_path_ok" != "1" ]; then
      echo "skills: refusing path outside skill roots: $repo_path (resolved=$_resolved_repo)" >> "$skills_log"
      skills_skipped=$((skills_skipped+1))
      continue
    fi

    if [ -n "$(git -C "$repo_path" status --porcelain 2>/dev/null)" ]; then
      echo "skills: $repo_name dirty — skipped" >> "$skills_log"
      skills_skipped=$((skills_skipped+1))
      continue
    fi
    if ! git -C "$repo_path" symbolic-ref --quiet HEAD >/dev/null 2>&1; then
      echo "skills: $repo_name detached HEAD — skipped" >> "$skills_log"
      skills_skipped=$((skills_skipped+1))
      continue
    fi

    if git -C "$repo_path" pull --ff-only origin "$branch" >> "$skills_log" 2>&1; then
      local new_version
      new_version=$(tr -d '[:space:]' < "$repo_path/VERSION" 2>/dev/null \
        || grep -m1 '"version"' "$repo_path/.claude-plugin/plugin.json" 2>/dev/null \
           | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' \
        || echo "?")
      echo "$repo_name $current_version → $new_version" >> "$upgraded_tools_file"
      skills_applied=$((skills_applied+1))
    else
      # v1.5.1 (codex P2): emit proper 4-tab TSV row that diagnose.sh
      # expects (tool\trc\tkind\tlog_path). The prior version echoed free
      # text with the repo name, which would have poisoned diagnose.sh's
      # parser if a repo name contained tabs or newlines.
      printf 'skills\t1\thard\t%s\n' "$skills_log" >> "$failure_log_file"
      skills_skipped=$((skills_skipped+1))
    fi
  done < <(jq -c '.skills.git_repos[]?' <<<"$discovery")

  # ────────────────────────────────────────────────────────────
  # PACKAGE DISPATCHER (hardcoded commands, never eval plan)
  # ────────────────────────────────────────────────────────────
  _run_tool() {
    local tool="$1"
    local log="$apply_log_root/${tool}.log"
    : > "$log"
    local rc=0

    _is_dropped "$tool" && return 0

    case "$tool" in
      brew)
        brew upgrade >> "$log" 2>&1; rc=$?
        if [ "$rc" = "0" ]; then
          grep -E "^==> Upgrading" "$log" 2>/dev/null \
            | awk '{print $3}' | cut -d/ -f1 >> "$upgraded_formulas_file"
        fi
        ;;
      npm)
        npm update -g >> "$log" 2>&1; rc=$?
        ;;
      pipx)
        pipx upgrade-all >> "$log" 2>&1; rc=$?
        ;;
      gems)
        local user_install
        user_install=$(jq -r '.tool_specs.gems.user_install // false' <<<"$plan")
        if [ "$user_install" = "true" ]; then
          gem update --user-install >> "$log" 2>&1; rc=$?
        else
          gem update >> "$log" 2>&1; rc=$?
        fi
        ;;
      uv)    uv self update >> "$log" 2>&1; rc=$? ;;
      bun)   bun upgrade >> "$log" 2>&1; rc=$? ;;
      mas)   mas upgrade >> "$log" 2>&1; rc=$? ;;
      macos) softwareupdate -ia >> "$log" 2>&1; rc=$? ;;
      # Linux user-scoped apps (no sudo). snap refresh may polkit-prompt in
      # the user's own session; flatpak update -y operates on the user install.
      snap)    snap refresh >> "$log" 2>&1; rc=$? ;;
      flatpak) flatpak update -y >> "$log" 2>&1; rc=$? ;;
      plugins)
        # v1.7: refresh the marketplace git source for each OUTDATED plugin.
        # This is the ONLY part of a plugin update that is safe to automate —
        # the reinstall (`/plugin update` + relaunch) has no headless path and
        # is surfaced as a manual step. Each marketplace is pulled once
        # (ff-only), dirty/detached trees are skipped, and the path is fenced
        # to MARKETPLACES_ROOT via canonical containment. A pull failure is
        # recorded per-marketplace and never fails the group (we don't want
        # the diagnoser firing on a source-refresh miss).
        local _mp_seen=" "
        local _pj _pname _mpath _resolved _mroot _ok
        while read -r _pj; do
          [ -z "$_pj" ] && continue
          _pname=$(jq -r '.name // "?"' <<<"$_pj")
          _mpath=$(jq -r '.marketplace_path // ""' <<<"$_pj")
          [ -z "$_mpath" ] && continue
          # Record before any branch so a repeated path — valid OR refused —
          # is handled exactly once (no duplicate rows in the report).
          case "$_mp_seen" in *" $_mpath "*) continue ;; esac
          _mp_seen="$_mp_seen$_mpath "
          _resolved=$(cd -P -- "$_mpath" 2>/dev/null && pwd -P)
          _mroot=$(cd -P -- "$MARKETPLACES_ROOT" 2>/dev/null && pwd -P)
          _ok=0
          if [ -n "$_resolved" ] && [ -n "$_mroot" ]; then
            case "$_resolved/" in "$_mroot/"*) _ok=1 ;; esac
          fi
          if [ "$_ok" != "1" ]; then
            echo "plugins: refusing marketplace path outside root: $_mpath" >> "$log"
            printf '%s\trefused\n' "$_mpath" >> "$plugins_refreshed_file"
            continue
          fi
          if [ ! -d "$_resolved/.git" ]; then
            printf '%s\tnot-git\n' "$_mpath" >> "$plugins_refreshed_file"
            continue
          fi
          if [ -n "$(git -C "$_resolved" status --porcelain 2>/dev/null)" ]; then
            echo "plugins: $_pname marketplace dirty — skipped ($_mpath)" >> "$log"
            printf '%s\tdirty-skipped\n' "$_mpath" >> "$plugins_refreshed_file"
            continue
          fi
          if ! git -C "$_resolved" symbolic-ref --quiet HEAD >/dev/null 2>&1; then
            printf '%s\tdetached-skipped\n' "$_mpath" >> "$plugins_refreshed_file"
            continue
          fi
          if git -C "$_resolved" pull --ff-only >> "$log" 2>&1; then
            printf '%s\tpulled\n' "$_mpath" >> "$plugins_refreshed_file"
          else
            printf '%s\tpull-failed\n' "$_mpath" >> "$plugins_refreshed_file"
          fi
        done < <(jq -c '.skills.managed[]?' <<<"$discovery")
        rc=0
        ;;
      skills) rc=0 ;;  # already ran above
      *)
        echo "refusing unknown tool: $tool" >> "$log"
        rc=1
        ;;
    esac

    if [ "$rc" = "0" ]; then
      # brew/skills/plugins keep their own accounting (formula list, skills
      # phase, plugins_refreshed_file) — don't double-count the literal id.
      [ "$tool" != "brew" ] && [ "$tool" != "skills" ] && [ "$tool" != "plugins" ] \
        && echo "$tool" >> "$upgraded_tools_file"
    else
      printf '%s\t%s\thard\t%s\n' "$tool" "$rc" "$log" >> "$failure_log_file"
    fi

    # Partial-failure detection (even on rc=0)
    case "$tool" in
      gems)
        grep -q "^ERROR:  Error installing" "$log" 2>/dev/null \
          && printf 'gems\t0\tpartial\t%s\n' "$log" >> "$failure_log_file" ;;
      npm)
        grep -qE "^npm (ERR|error)" "$log" 2>/dev/null \
          && printf 'npm\t0\tpartial\t%s\n' "$log" >> "$failure_log_file" ;;
      brew)
        grep -qE "^Error: " "$log" 2>/dev/null \
          && printf 'brew\t0\tpartial\t%s\n' "$log" >> "$failure_log_file" ;;
      pipx)
        grep -qE "^(Error|⚠)" "$log" 2>/dev/null \
          && printf 'pipx\t0\tpartial\t%s\n' "$log" >> "$failure_log_file" ;;
    esac

    # Deprecation aggregator
    grep -iE "(deprecat|warning|WARN)" "$log" 2>/dev/null >> "$deprecation_log"
  }

  # Iterate ordered groups
  local group_idx=0 group_count
  group_count=$(jq '.ordered_groups | length' <<<"$plan")
  while [ "$group_idx" -lt "$group_count" ]; do
    local group parallelism tools
    group=$(jq -c ".ordered_groups[$group_idx]" <<<"$plan")
    parallelism=$(jq -r '.parallelism' <<<"$group")
    tools=$(jq -r '.tools[]' <<<"$group")

    case "$parallelism" in
      parallel)
        local pids=()
        local concurrency=0
        for tool in $tools; do
          _run_tool "$tool" &
          pids+=($!)
          concurrency=$((concurrency+1))
          if [ "$concurrency" -ge 4 ]; then
            wait "${pids[0]}"
            pids=("${pids[@]:1}")
            concurrency=$((concurrency-1))
          fi
        done
        # v1.6: guard against bash 3.2's "unbound variable" on expanding an
        # empty array under `set -u` (the dev box ships bash 3.2.57). The
        # synthesizer never emits an empty-tools group, but a future caller
        # might — this keeps the drain safe regardless.
        if [ "${#pids[@]}" -gt 0 ]; then
          for pid in "${pids[@]}"; do wait "$pid"; done
        fi
        ;;
      serial|exclusive)
        for tool in $tools; do _run_tool "$tool"; done
        ;;
      *) _die "unknown parallelism: $parallelism" ;;
    esac
    group_idx=$((group_idx+1))
  done

  # ────────────────────────────────────────────────────────────
  # POST-FLIGHT (Step 4m verbatim, condensed)
  # ────────────────────────────────────────────────────────────
  local doctor_out=""
  if command -v brew >/dev/null 2>&1 && [ -n "$(cat "$upgraded_formulas_file" 2>/dev/null)" ]; then
    doctor_out=$(brew doctor 2>&1)
    case "$doctor_out" in
      *"Your system is ready to brew."*) doctor_out="" ;;
    esac
  fi

  local upgraded_formulas
  upgraded_formulas=$(sort -u "$upgraded_formulas_file" | tr '\n' ' ')
  local upgraded_tools
  upgraded_tools=$(sort -u "$upgraded_tools_file" | tr '\n' ' ')

  local shadow_hits='[]'
  if [ -n "$upgraded_formulas" ] && command -v brew >/dev/null 2>&1; then
    local brew_prefix
    brew_prefix=$(brew --prefix 2>/dev/null)
    local shadow_lines=""
    for formula in $upgraded_formulas; do
      local bins
      bins=$(brew list "$formula" 2>/dev/null | grep "/bin/" | xargs -n1 basename 2>/dev/null | sort -u)
      for bin in $bins; do
        local paths first
        paths=$(which -a "$bin" 2>/dev/null | sort -u)
        local count
        count=$(echo "$paths" | grep -c . 2>/dev/null)
        if [ "${count:-0}" -gt 1 ]; then
          first=$(echo "$paths" | head -1)
          local brew_path="$brew_prefix/bin/$bin"
          if [ "$first" != "$brew_path" ]; then
            shadow_lines+="$bin (first: $first, brew: $brew_path)\n"
          fi
        fi
      done
    done
    if [ -n "$shadow_lines" ]; then
      shadow_hits=$(printf '%b' "$shadow_lines" | jq -R '.' | jq -s -c '.')
    fi
  fi

  local resolution_failures='[]'
  local res_lines=""
  for t in $upgraded_tools; do
    case "$t" in
      */*|*→*) continue ;;  # skip "skill name → version" entries
    esac
    if ! command -v "$t" >/dev/null 2>&1; then
      res_lines+="$t\n"
    fi
  done
  [ -n "$res_lines" ] && resolution_failures=$(printf '%b' "$res_lines" | jq -R '.' | jq -s -c '.')

  # ────────────────────────────────────────────────────────────
  # FAILURE DIAGNOSIS (replaces v1.4 Step 4.5m LLM agent)
  # ────────────────────────────────────────────────────────────
  local diagnoses_json='{"diagnoses":[],"errors":[]}'
  if [ -s "$failure_log_file" ]; then
    diagnoses_json=$(bash "$SCRIPT_DIR/diagnose.sh" < "$failure_log_file" 2>/dev/null \
      || echo '{"diagnoses":[],"errors":["diagnose.sh failed"]}')
  fi

  # ────────────────────────────────────────────────────────────
  # HISTORY WRITE (Step 5m flock-guarded)
  # ────────────────────────────────────────────────────────────
  if command -v jq >/dev/null 2>&1; then
    local hist_file="$DATA_DIR/upkeep-history.json"
    local hist_lock="$DATA_DIR/upkeep-history.lock"
    mkdir -p "$DATA_DIR" 2>/dev/null
    local entry
    # v1.5.1: .language.errors is an array (not an object), and
    # `.value.outdated` on an array fails with "Cannot index array with
    # string". Filter to object values first. Similarly defend the brew
    # path against a missing .outdated key.
    entry=$(jq -n --arg ts "$(date -u +%FT%TZ)" \
      --argjson formulas "$(jq '(.native.brew.outdated // []) | length' <<<"$discovery")" \
      --argjson tools "$(jq '.language | [.[] | select(type == "object") | (.outdated // []) | length] | add // 0' <<<"$discovery")" \
      '{ts:$ts, brew_count:$formulas, lang_count:$tools}')
    _write_history() {
      local tmp rc=0
      tmp=$(mktemp "${DATA_DIR}/.upkeep-history.XXXXXX") || return 1
      if [ -f "$hist_file" ]; then
        if ! jq --argjson e "$entry" '.runs += [$e]' "$hist_file" > "$tmp"; then rc=$?; fi
      else
        if ! jq -n --argjson e "$entry" '{schema_version:"1", runs:[$e]}' > "$tmp"; then rc=$?; fi
      fi
      if [ "$rc" = "0" ]; then
        mv -- "$tmp" "$hist_file" || rc=$?
      fi
      # v1.5.1: clean up the mktemp on any failure path so we don't
      # leave 0-byte .upkeep-history.XXXXXX orphans in DATA_DIR.
      if [ "$rc" != "0" ] && [ -f "$tmp" ]; then
        rm -f -- "$tmp"
      fi
      return $rc
    }
    # Sweep stale orphans (>1h old) — defense for prior buggy versions
    # that left them behind. New code paths above no longer create them.
    find "$DATA_DIR" -maxdepth 1 -name '.upkeep-history.*' -mmin +60 -delete 2>/dev/null
    if command -v flock >/dev/null 2>&1; then
      ( flock -x 9; _write_history ) 9>"$hist_lock"
    else
      _write_history
    fi
  fi

  # ────────────────────────────────────────────────────────────
  # PLUGINS REPORT DATA (v1.7)
  # ────────────────────────────────────────────────────────────
  # `outdated` is the full hand-off list (survives even if the user dropped
  # the plugins category — they still need the /plugin update commands).
  # `marketplaces_refreshed` reflects what the apply phase actually pulled.
  local plugins_outdated_json plugins_refreshed_json
  plugins_outdated_json=$(jq -c '[.skills.managed[]?
    | {name, installed_version, available_version, update_command}]' <<<"$discovery")
  plugins_refreshed_json=$(awk -F'\t' 'NF>=2 {n=$1; sub(/.*\//,"",n); printf "%s\t%s\n", n, $2}' \
      "$plugins_refreshed_file" 2>/dev/null \
    | jq -Rsc 'split("\n") | map(select(length>0) | split("\t")
               | {marketplace:.[0], status:.[1]})')
  [ -z "$plugins_refreshed_json" ] && plugins_refreshed_json='[]'

  # ────────────────────────────────────────────────────────────
  # REPORT JSON for SKILL.md to render
  # ────────────────────────────────────────────────────────────
  jq -n \
    --arg mode "$mode" \
    --argjson skills_applied "$skills_applied" \
    --argjson skills_skipped "$skills_skipped" \
    --argjson plugins_outdated "$plugins_outdated_json" \
    --argjson plugins_refreshed "$plugins_refreshed_json" \
    --argjson upgraded_formulas "$(echo "$upgraded_formulas" | tr ' ' '\n' | grep -v '^$' | jq -R '.' | jq -s -c '.')" \
    --argjson upgraded_tools "$(echo "$upgraded_tools" | tr ' ' '\n' | grep -v '^$' | jq -R '.' | jq -s -c '.')" \
    --argjson diagnoses "$diagnoses_json" \
    --argjson shadow_hits "$shadow_hits" \
    --argjson resolution_failures "$resolution_failures" \
    --arg doctor "$doctor_out" \
    '{
      mode: $mode,
      skills: {applied: $skills_applied, skipped: $skills_skipped},
      plugins: {
        outdated: $plugins_outdated,
        marketplaces_refreshed: $plugins_refreshed,
        note: (if ($plugins_outdated | length) > 0
               then "Marketplace sources refreshed where possible. To finish each update, run the listed /plugin update command(s) then relaunch Claude Code — the plugin cache reinstall has no headless path."
               else null end)
      },
      upgraded_formulas: $upgraded_formulas,
      upgraded_tools: $upgraded_tools,
      doctor: (if ($doctor | length) > 0 then $doctor else null end),
      shadow_hits: $shadow_hits,
      resolution_failures: $resolution_failures,
      diagnoses: $diagnoses.diagnoses,
      diagnosis_errors: $diagnoses.errors
    }
    | walk(
        if type == "string"
        then (gsub("[[:cntrl:]]"; "") | .[0:512])
        else .
        end
      )'

  # Plan file has served its purpose — remove. The EXIT trap on
  # $TMP_ROOT_APPLY handles the apply workspace; the plan file lives
  # in $DATA_DIR and isn't covered by that trap.
  rm -f -- "$plan_file" 2>/dev/null
}

# ───────────────────────────────────────────────────────────────────
# ENTRY POINT
# ───────────────────────────────────────────────────────────────────
case "${1:-}" in
  plan)  shift; _cmd_plan "$@" ;;
  apply) shift; _cmd_apply "$@" ;;
  ""|help|--help)
    cat <<'EOF' >&2
upkeep/update.sh — single-shot orchestrator (v1.5)

Usage:
  update.sh plan <audit|skills|packages|all> [--no-cache] [--fresh]
  update.sh apply <plan-file> [--drop=tool1,tool2] [--advisor]

Environment:
  UPKEEP_BREW_TTL             brew update cache TTL in seconds (default 3600)
  UPKEEP_NO_CACHE             set to 1 to force brew update refresh
  UPKEEP_FRESH_MARKETPLACES   set to 1 (or pass --fresh) to git-fetch plugin
                              marketplaces and compare against upstream
  UPKEEP_DATA_DIR             plan/history directory (default ~/.claude/data)
EOF
    exit 64
    ;;
  *) _die "unknown command: $1 (expected: plan|apply)" ;;
esac
