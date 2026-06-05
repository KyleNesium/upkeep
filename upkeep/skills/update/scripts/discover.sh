#!/usr/bin/env bash
# upkeep discovery — macOS fast path (v1.4)
#
# Replaces the four scout agents from v1.3 (skills, native, language, shadow).
# Inline bash + jq runs the whole sweep in ~3 seconds instead of ~90 seconds
# of LLM agent overhead.
#
# Output: combined discovery JSON on stdout (schema_version "1").
# Stderr: human diagnostic messages only.
# Exit:   0 on success, 1 on hard failure (missing jq, refusing disk).

set -uo pipefail

TRUST_FILE="${UPKEEP_TRUST_FILE:-$HOME/.claude/data/upkeep-skill-trust.json}"
CLAUDE_SKILLS_ROOT="${UPKEEP_CLAUDE_SKILLS:-$HOME/.claude/skills}"
CODEX_SKILLS_ROOT="${UPKEEP_CODEX_SKILLS:-$HOME/.codex/skills}"
PLUGIN_CACHE_ROOT="${UPKEEP_PLUGIN_CACHE:-$HOME/.claude/plugins/cache}"
# v1.7: plugin update detection reads the authoritative install state
# (installed_plugins.json) and compares each plugin's active version against
# the version declared in its marketplace's on-disk marketplace.json. Test
# seams let the suite point these at fixtures.
INSTALLED_PLUGINS_FILE="${UPKEEP_INSTALLED_PLUGINS:-$HOME/.claude/plugins/installed_plugins.json}"
MARKETPLACES_ROOT="${UPKEEP_PLUGIN_MARKETPLACES:-$HOME/.claude/plugins/marketplaces}"
SCOUT_MAX_REPOS="${UPKEEP_MAX_REPOS:-200}"

if ! command -v jq >/dev/null 2>&1; then
  # v1.5.1: emit JSON to stdout (callers reading `.schema_version` see
  # `null`; callers reading `.error` get a clear message); prose to
  # stderr.
  printf '%s\n' '{"error":"jq required but not found"}'
  echo "discover.sh: jq is required" >&2
  exit 1
fi

# ── Disk pre-flight ──────────────────────────────────────────────
free_gb=$(df -k / 2>/dev/null | awk 'NR==2 {print int($4/1024/1024)}')
free_gb=${free_gb:-0}
disk_json=$(jq -n \
  --argjson free "$free_gb" \
  --argjson warn 10 \
  --argjson refuse 5 \
  '{free_gb:$free, warn_threshold_gb:$warn, refuse_threshold_gb:$refuse}')

# ── Helpers ──────────────────────────────────────────────────────
_jq_string() { jq -Rs '.' <<<"$1"; }

# Plugin version resolution helpers (v1.7.1). A marketplace.json entry may
# declare a plugin's version inline, OR omit it and rely on the plugin's own
# plugin.json under its `source` subdir. These parse marketplace.json CONTENT
# (string in $1) for plugin name ($2).
_mp_inline_version() {
  jq -r --arg p "$2" '.plugins[]? | select(.name == $p) | .version // empty' \
    <<<"$1" 2>/dev/null | head -1
}
# Source subdir for a plugin, normalized: leading "./" and trailing "/"
# stripped, so "./" → "" (marketplace root), "./foo/" → "foo".
#
# `source` is a marketplace-controlled field, so it is treated as untrusted:
# a value containing a ".." path segment or an absolute path is REJECTED
# (returns empty) so it can't make discovery read a plugin.json outside the
# marketplace tree. Empty → caller reads the marketplace-root plugin.json,
# which is always contained within the marketplace dir.
_mp_plugin_source() {
  local s
  s=$(jq -r --arg p "$2" '.plugins[]? | select(.name == $p) | .source // "./"' \
    <<<"$1" 2>/dev/null | head -1)
  s="${s#./}"; s="${s%/}"
  case "/$s/" in */../*) s="" ;; esac   # reject any ".." segment
  case "$s"    in /*)     s="" ;; esac   # reject absolute path
  printf '%s' "$s"
}
# Relative path to a plugin's own plugin.json given its (normalized) source.
_pj_relpath() {
  if [ -n "$1" ]; then printf '%s/.claude-plugin/plugin.json' "$1"
  else printf '.claude-plugin/plugin.json'; fi
}

# Detect arch
ARCH=$(uname -m 2>/dev/null || echo unknown)

# ── OS detection (v1.6) ──────────────────────────────────────────
# Sets OS_TYPE (macos|linux|wsl2|unknown), OS_DISTRO, PKG_MGR. Mirrors
# the shared block used across the cleanup skills.
#
# Test seam: UPKEEP_OS_OVERRIDE / UPKEEP_PKG_MGR_OVERRIDE short-circuit
# the live `uname` so Linux paths can be exercised on a macOS box (where
# `uname -s` always reports Darwin). The override forces BOTH the emitted
# os.type AND which native-discovery function the parallel runner picks —
# stamping os.type alone would never run discover_native_linux on macOS.
_detect_os() {
  if [ -n "${UPKEEP_OS_OVERRIDE:-}" ]; then
    OS_TYPE="$UPKEEP_OS_OVERRIDE"
    OS_DISTRO="${UPKEEP_OS_DISTRO_OVERRIDE:-override}"
  else
    local kernel krel
    kernel=$(uname -s 2>/dev/null || echo "unknown")
    krel=$(uname -r 2>/dev/null || echo "")
    case "$kernel" in
      Darwin) OS_TYPE="macos"; OS_DISTRO="macos" ;;
      Linux)
        if echo "$krel" | grep -qi "microsoft"; then OS_TYPE="wsl2"; else OS_TYPE="linux"; fi
        if [ -r /etc/os-release ]; then
          OS_DISTRO=$(. /etc/os-release 2>/dev/null; echo "${ID_LIKE:-$ID}" | awk '{print $1}')
        elif command -v lsb_release >/dev/null 2>&1; then
          OS_DISTRO=$(lsb_release -si 2>/dev/null | tr '[:upper:]' '[:lower:]')
        else
          OS_DISTRO="unknown"
        fi
        ;;
      *) OS_TYPE="unknown"; OS_DISTRO="unknown" ;;
    esac
  fi

  if [ -n "${UPKEEP_PKG_MGR_OVERRIDE:-}" ]; then
    PKG_MGR="$UPKEEP_PKG_MGR_OVERRIDE"
  else
    case "$OS_DISTRO" in
      debian|ubuntu)                          PKG_MGR="apt" ;;
      fedora|rhel|centos|rocky|almalinux)     PKG_MGR="dnf" ;;
      arch|manjaro|endeavouros)               PKG_MGR="pacman" ;;
      macos)                                  PKG_MGR="brew" ;;
      *)                                      PKG_MGR="unknown" ;;
    esac
  fi
}
_detect_os

# ── Skills section ───────────────────────────────────────────────
discover_skills() {
  local trust_json='{}'
  if [ -f "$TRUST_FILE" ]; then
    trust_json=$(jq -c '.' "$TRUST_FILE" 2>/dev/null || echo '{}')
  fi

  local git_repos='[]' managed='[]'
  local claude_plugins_count=0 codex_total=0 codex_git=0

  # ── Git-cloned skills under both roots ──
  local root
  for root in "$CLAUDE_SKILLS_ROOT" "$CODEX_SKILLS_ROOT"; do
    [ -d "$root" ] || continue
    local mgr="claude"
    [ "$root" = "$CODEX_SKILLS_ROOT" ] && mgr="codex"

    local d name path remote_url branch trusted dirty detached current_ver behind subjects
    for d in "$root"/*/; do
      [ -d "$d/.git" ] || continue
      name=$(basename "$d")
      path="${d%/}"
      remote_url=$(git -C "$path" remote get-url origin 2>/dev/null || echo "")
      [ -z "$remote_url" ] && continue

      trusted="false"
      if jq -e --arg url "$remote_url" '.[$url] // empty' <<<"$trust_json" >/dev/null 2>&1; then
        trusted="true"
      fi

      dirty=$(git -C "$path" status --porcelain 2>/dev/null | head -20)
      detached="false"
      git -C "$path" symbolic-ref --quiet HEAD >/dev/null 2>&1 || detached="true"

      branch=""
      [ "$detached" = "false" ] && branch=$(git -C "$path" symbolic-ref --short HEAD 2>/dev/null || echo "")

      current_ver=$(tr -d '[:space:]' < "$path/VERSION" 2>/dev/null \
        || (jq -r '.version // empty' "$path/.claude-plugin/plugin.json" 2>/dev/null) \
        || echo "")

      behind=0
      subjects='[]'
      breaking_lines='[]'
      if [ "$trusted" = "true" ] && [ "$detached" = "false" ] && [ -n "$branch" ]; then
        GIT_TERMINAL_PROMPT=0 git -C "$path" fetch --tags -q origin 2>/dev/null
        behind=$(git -C "$path" rev-list --count "HEAD..origin/$branch" 2>/dev/null || echo 0)
        if [ "$behind" -gt 0 ]; then
          subjects=$(git -C "$path" log "HEAD..origin/$branch" --format='%s' -5 2>/dev/null \
            | jq -Rsc 'split("\n") | map(select(length > 0))')
          if [ -f "$path/CHANGELOG.md" ]; then
            breaking_lines=$(grep -E "BREAKING|Breaking" "$path/CHANGELOG.md" 2>/dev/null \
              | head -5 | jq -Rsc 'split("\n") | map(select(length > 0))')
          fi
        fi
      fi

      local dirty_arr untrusted_field
      dirty_arr=$(printf '%s\n' "$dirty" | jq -Rsc 'split("\n") | map(select(length > 0))')
      [ "$trusted" = "true" ] && untrusted_field="false" || untrusted_field="true"

      local entry
      entry=$(jq -n \
        --arg name "$name" \
        --arg path "$path" \
        --arg branch "$branch" \
        --arg remote_url "$remote_url" \
        --argjson untrusted "$untrusted_field" \
        --arg current_version "$current_ver" \
        --argjson commits_behind "$behind" \
        --argjson newest_commit_subjects "$subjects" \
        --argjson breaking_lines "$breaking_lines" \
        --argjson dirty_files "$dirty_arr" \
        --argjson detached "$detached" \
        --arg manager "$mgr" \
        '{name:$name, path:$path, branch:$branch, remote_url:$remote_url,
          untrusted:$untrusted, current_version:$current_version,
          commits_behind:$commits_behind,
          newest_commit_subjects:$newest_commit_subjects,
          breaking_lines:$breaking_lines, dirty_files:$dirty_files,
          detached:$detached, remote_ok:true, manager:$manager}')
      git_repos=$(jq --argjson entry "$entry" '. + [$entry]' <<<"$git_repos")

      [ "$mgr" = "codex" ] && codex_git=$((codex_git + 1))
    done
  done

  # ── Claude Code plugins — OUTDATED detection (v1.7) ──
  # Prior versions (≤1.6) walked the plugin cache and emitted EVERY
  # installed plugin as a "/plugin update" manual step, regardless of
  # whether it was actually behind. That told users to update 18 plugins
  # when maybe two were stale.
  #
  # v1.7 compares the authoritative active version (installed_plugins.json)
  # against the version each plugin's marketplace declares on disk
  # (marketplace.json). Only genuinely-behind plugins land in `managed`.
  #
  # Hard limit (verified against Claude Code internals): there is NO
  # supported headless way to APPLY a plugin update — `/plugin update` is
  # interactive and the reinstall needs a Claude Code relaunch. So `managed`
  # is a "prep + hand off" list: the apply phase refreshes the marketplace
  # git source (safe, ff-only), and the user runs the consolidated
  # `/plugin update` command + relaunches to finish.
  # UPKEEP_FRESH_MARKETPLACES=1 (the `--fresh` flag) fetches each
  # marketplace and reads the available version from its upstream tracking
  # ref instead of the on-disk manifest — catching updates the local clone
  # hasn't pulled yet. Off by default (network latency); same
  # fetch-during-discovery precedent as the trusted-skill section above.
  local fresh_mps="${UPKEEP_FRESH_MARKETPLACES:-0}"
  local _fetched_mps=" "
  local plugins_outdated_count=0
  if [ -f "$INSTALLED_PLUGINS_FILE" ]; then
    # Rows: name<TAB>marketplace<TAB>installed_version. The installed_plugins
    # key is "<plugin>@<marketplace>"; plugin names never contain "@", and
    # everything after the last "@" is the marketplace id.
    local pl_name pl_market pl_installed mp_json pl_available mp_path mp_is_git
    while IFS=$'\t' read -r pl_name pl_market pl_installed; do
      [ -z "$pl_name" ] && continue
      mp_path="$MARKETPLACES_ROOT/$pl_market"
      mp_json="$mp_path/.claude-plugin/marketplace.json"
      pl_available=""
      # Prefer the upstream manifest under --fresh; fetch each marketplace
      # at most once per run. Version comes from the marketplace.json inline
      # `version`, or — when that's omitted — the plugin's own plugin.json
      # under its `source` subdir.
      if [ "$fresh_mps" = "1" ] && [ -d "$mp_path/.git" ]; then
        case "$_fetched_mps" in
          *" $mp_path "*) ;;  # already fetched this marketplace this run
          *) GIT_TERMINAL_PROMPT=0 git -C "$mp_path" fetch -q 2>/dev/null
             _fetched_mps="$_fetched_mps$mp_path " ;;
        esac
        local _up_json _src _pj
        _up_json=$(git -C "$mp_path" show "@{u}:.claude-plugin/marketplace.json" 2>/dev/null)
        if [ -n "$_up_json" ]; then
          pl_available=$(_mp_inline_version "$_up_json" "$pl_name")
          if [ -z "$pl_available" ]; then
            _src=$(_mp_plugin_source "$_up_json" "$pl_name")
            _pj=$(git -C "$mp_path" show "@{u}:$(_pj_relpath "$_src")" 2>/dev/null)
            [ -n "$_pj" ] && pl_available=$(jq -r '.version // empty' <<<"$_pj" 2>/dev/null)
          fi
        fi
      fi
      # Fall back to the on-disk manifest when not fresh, or when fresh
      # yielded nothing (no upstream, non-git marketplace, fetch failure).
      if [ -z "$pl_available" ] && [ -f "$mp_json" ]; then
        local _mp_content _src2 _pj_file
        _mp_content=$(cat "$mp_json" 2>/dev/null)
        pl_available=$(_mp_inline_version "$_mp_content" "$pl_name")
        if [ -z "$pl_available" ]; then
          _src2=$(_mp_plugin_source "$_mp_content" "$pl_name")
          _pj_file="$mp_path/$(_pj_relpath "$_src2")"
          [ -f "$_pj_file" ] && pl_available=$(jq -r '.version // empty' "$_pj_file" 2>/dev/null)
        fi
      fi
      claude_plugins_count=$((claude_plugins_count + 1))

      # Decide outdated. Skip when we can't compare (no marketplace data).
      local is_outdated=0
      if [ -z "$pl_available" ] || [ "$pl_available" = "unknown" ]; then
        # No comparable marketplace version (missing, or the literal sentinel
        # Claude Code writes for un-versioned plugins). `sort -V` orders the
        # string "unknown" AFTER any real semver, so without this guard a
        # plugin installed at e.g. 2.0.0 against a marketplace declaring
        # "unknown" would be mis-flagged as "2.0.0 → unknown".
        is_outdated=0
      elif [ "$pl_installed" = "$pl_available" ]; then
        is_outdated=0
      elif [ "$pl_installed" = "unknown" ] || [ -z "$pl_installed" ]; then
        # Active version unknowable but marketplace has a concrete version →
        # flag it so the user can reconcile.
        is_outdated=1
      else
        local _highest
        _highest=$(printf '%s\n%s\n' "$pl_installed" "$pl_available" | sort -V | tail -1)
        if [ "$_highest" = "$pl_available" ] && [ "$_highest" != "$pl_installed" ]; then
          is_outdated=1
        fi
      fi
      [ "$is_outdated" = "1" ] || continue

      mp_is_git=false
      [ -d "$mp_path/.git" ] && mp_is_git=true

      managed=$(jq --arg name "$pl_name" --arg market "$pl_market" \
        --arg installed "$pl_installed" --arg available "$pl_available" \
        --arg mp_path "$mp_path" --argjson mp_is_git "$mp_is_git" \
        '. + [{name:$name, manager:"claude-code-plugin", marketplace:$market,
               installed_version:$installed, available_version:$available,
               marketplace_path:$mp_path, marketplace_is_git:$mp_is_git,
               update_command:("/plugin update " + $name)}]' <<<"$managed")
      plugins_outdated_count=$((plugins_outdated_count + 1))
    done < <(jq -r '
      (.plugins // {}) | to_entries[]
      | (.key | (rindex("@")) as $i
         | if $i == null then {n: ., m: "unknown"}
           else {n: .[0:$i], m: .[$i+1:]} end) as $p
      | [$p.n, (if ($p.m | length) > 0 then $p.m else "unknown" end),
         (.value[0].version // "unknown")]
      | @tsv' "$INSTALLED_PLUGINS_FILE" 2>/dev/null)
  fi

  # Counts
  if [ -d "$CODEX_SKILLS_ROOT" ]; then
    codex_total=$(find "$CODEX_SKILLS_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  fi

  jq -n \
    --argjson git_repos "$git_repos" \
    --argjson managed "$managed" \
    --argjson claude_plugins "$claude_plugins_count" \
    --argjson plugins_outdated "${plugins_outdated_count:-0}" \
    --argjson codex_total "$codex_total" \
    --argjson codex_git "$codex_git" \
    '{git_repos:$git_repos, managed:$managed,
      info:{claude_plugins:$claude_plugins, plugins_outdated:$plugins_outdated,
            codex_skills_total:$codex_total, codex_skills_git:$codex_git},
      errors:[]}'
}

# ── Semver bump classifier ───────────────────────────────────────
# Args: from to → echoes "major" | "minor" | "patch"
_bump_class() {
  local from="$1" to="$2"
  # Strip everything after first non-numeric/dot/-
  local f_major f_minor t_major t_minor
  f_major=$(echo "$from" | awk -F'[._-]' '{print $1}' | tr -cd '0-9')
  f_minor=$(echo "$from" | awk -F'[._-]' '{print $2}' | tr -cd '0-9')
  t_major=$(echo "$to"   | awk -F'[._-]' '{print $1}' | tr -cd '0-9')
  t_minor=$(echo "$to"   | awk -F'[._-]' '{print $2}' | tr -cd '0-9')
  [ -z "$f_major" ] && f_major=0
  [ -z "$t_major" ] && t_major=0
  [ -z "$f_minor" ] && f_minor=0
  [ -z "$t_minor" ] && t_minor=0
  if [ "$f_major" != "$t_major" ]; then echo major
  elif [ "$f_minor" != "$t_minor" ]; then echo minor
  else echo patch
  fi
}

# ── Native section (brew, mas, softwareupdate) ───────────────────
discover_native() {
  local brew_installed=false mas_installed=false sw_installed=true
  local brew_outdated='[]' mas_outdated='[]' sw_updates='[]'
  local restart_required=false
  local errors='[]'

  if command -v brew >/dev/null 2>&1; then
    brew_installed=true
    # CRITICAL FIX from v1.3: refresh metadata FIRST so outdated list is accurate.
    # v1.5: TTL-cache `brew update` (8–14s wall) against brew's own formula.jws.json
    # mtime. Default 1h; bypass with UPKEEP_NO_CACHE=1. Sentinel is the JSON file
    # `brew update` already writes — no separate timestamp file needed.
    local brew_sentinel="$HOME/Library/Caches/Homebrew/api/formula.jws.json"
    local brew_ttl="${UPKEEP_BREW_TTL:-3600}"  # seconds
    local brew_ttl_min=$(( brew_ttl / 60 ))
    [ "$brew_ttl_min" -lt 1 ] && brew_ttl_min=1
    local skip_update=0
    if [ "${UPKEEP_NO_CACHE:-0}" != "1" ] && \
       [ -n "$(find "$brew_sentinel" -mmin -"$brew_ttl_min" 2>/dev/null)" ]; then
      skip_update=1
    fi
    if [ "$skip_update" = "0" ]; then
      brew update >/dev/null 2>&1 || errors=$(jq '. + ["brew update failed"]' <<<"$errors")
    fi

    local brew_json
    brew_json=$(brew outdated --json=v2 2>/dev/null || echo '{"formulae":[],"casks":[]}')
    # Formulae
    local formulae casks
    formulae=$(jq -c '[.formulae[]? | {name, installed_versions: (.installed_versions // []), current_version: (.current_version // "")}]' <<<"$brew_json" 2>/dev/null || echo '[]')
    casks=$(jq -c '[.casks[]? | {name, installed_versions: (.installed_versions // []), current_version: (.current_version // "")}]' <<<"$brew_json" 2>/dev/null || echo '[]')

    local row name from to bump
    while IFS=$'\t' read -r name from to; do
      [ -z "$name" ] && continue
      bump=$(_bump_class "$from" "$to")
      brew_outdated=$(jq --arg name "$name" --arg from "$from" --arg to "$to" --arg bump "$bump" \
        '. + [{name:$name, from:$from, to:$to, bump:$bump}]' <<<"$brew_outdated")
    done < <(jq -r '.[] | [.name, (.installed_versions | .[0] // ""), .current_version] | @tsv' <<<"$formulae")

    while IFS=$'\t' read -r name from to; do
      [ -z "$name" ] && continue
      bump=$(_bump_class "$from" "$to")
      brew_outdated=$(jq --arg name "$name" --arg from "$from" --arg to "$to" --arg bump "$bump" \
        '. + [{name:$name, from:$from, to:$to, bump:$bump}]' <<<"$brew_outdated")
    done < <(jq -r '.[] | [.name, (.installed_versions | .[0] // ""), .current_version] | @tsv' <<<"$casks")
  fi

  if command -v mas >/dev/null 2>&1; then
    mas_installed=true
    local mas_raw
    mas_raw=$(mas outdated 2>/dev/null)
    if [ -n "$mas_raw" ]; then
      mas_outdated=$(jq -Rsc 'split("\n") | map(select(length > 0) | {name: .})' <<<"$mas_raw")
    fi
  fi

  local sw_raw sw_lines
  sw_raw=$(softwareupdate -l 2>&1 || true)
  if echo "$sw_raw" | grep -qiE "restart"; then
    restart_required=true
  fi
  # Note: do NOT chain `|| echo '[]'` after a pipeline here. With set -o pipefail,
  # a non-matching grep fails the pipeline AND the fallback fires — both jq's
  # output and echo's output get captured, producing invalid JSON like "[]\n[]".
  # jq -Rsc on empty input already returns "[]", so no fallback is needed.
  sw_lines=$(echo "$sw_raw" | grep -E "^\s*\*" || true)
  sw_updates=$(printf '%s' "$sw_lines" | jq -Rsc 'split("\n") | map(select(length > 0))')

  jq -n \
    --argjson brew_installed "$brew_installed" \
    --argjson brew_outdated "$brew_outdated" \
    --argjson mas_installed "$mas_installed" \
    --argjson mas_outdated "$mas_outdated" \
    --argjson sw_installed "$sw_installed" \
    --argjson sw_updates "$sw_updates" \
    --argjson restart "$restart_required" \
    --argjson errors "$errors" \
    '{brew:{installed:$brew_installed, outdated:$brew_outdated},
      mas:{installed:$mas_installed, outdated:$mas_outdated},
      softwareupdate:{installed:$sw_installed, updates:$sw_updates, restart_required:$restart},
      errors:$errors}'
}

# ── Native section — Linux/WSL2 (apt/dnf/pacman + snap/flatpak) ──
# Mirrors discover_native's contract but for Linux. Key invariant: the
# system manager (apt/dnf/pacman) requires root to upgrade, so it is
# reported here for the synthesizer to surface as a MANUAL step — it is
# never auto-applied. snap/flatpak are user-scoped and ARE auto-applied.
#
# Exit-code discipline (v1.6):
#   - `dnf check-update` exits 100 when updates exist (0 = none). Capture
#     rc and treat 100 as success, anything else as error.
#   - `grep`/`pacman -Qu`/`snap refresh --list` return 1 on no-match; under
#     `set -o pipefail` that fails the pipeline, so every extraction ends
#     with `|| true` and feeds `jq -Rsc 'split…|map(select(length>0))'`,
#     which yields `[]` on empty input. Never `|| echo '[]'` after a
#     pipeline (would emit `[]\n[]` → invalid JSON; see discover_native).
discover_native_linux() {
  local manager="${PKG_MGR:-unknown}"
  local sys_installed=false sys_upgradable='[]' sys_count=0
  local snap_installed=false snap_refreshable='[]'
  local flatpak_installed=false flatpak_updatable='[]'
  local errors='[]'

  # ── System package manager (audit only — upgrade needs sudo) ──
  case "$manager" in
    apt)
      if command -v apt-get >/dev/null 2>&1; then
        sys_installed=true
        local apt_raw
        apt_raw=$(apt-get upgrade --dry-run 2>/dev/null | grep '^Inst' || true)
        if [ -n "$apt_raw" ]; then
          # "Inst <name> [<from>] (<to> <repo> [arch])". The version bracket
          # [<from>] sits BEFORE the "("; the arch bracket [amd64] sits
          # INSIDE the parens. Split at the first "(" so a from-less line
          # (new dep: "Inst x (1.0 ...)") doesn't mis-read [arch] as <from>.
          sys_upgradable=$(printf '%s\n' "$apt_raw" | awk '
            {
              name=$2; from=""; to=""
              p=index($0, "(")
              pre=(p>0)?substr($0,1,p-1):$0
              post=(p>0)?substr($0,p):""
              if (match(pre, /\[[^]]*\]/))  { from=substr(pre, RSTART+1, RLENGTH-2) }
              if (match(post, /\([^ )]+/))  { to=substr(post, RSTART+1, RLENGTH-1) }
              printf "%s\t%s\t%s\n", name, from, to
            }' \
            | jq -Rsc 'split("\n") | map(select(length>0) | split("\t")
                       | {name:.[0], from:(.[1]//""), to:(.[2]//"")})')
        fi
      fi
      ;;
    dnf)
      if command -v dnf >/dev/null 2>&1; then
        sys_installed=true
        local dnf_raw dnf_rc
        dnf_raw=$(dnf check-update 2>/dev/null); dnf_rc=$?
        if [ "$dnf_rc" != "0" ] && [ "$dnf_rc" != "100" ]; then
          errors=$(jq '. + ["dnf check-update failed"]' <<<"$errors")
        fi
        # Rows: "name.arch  version-release  repo". `dnf check-update`
        # appends an "Obsoleting Packages" section after the upgrade list;
        # those rows are NOT separate upgrades, so stop parsing once we hit
        # that header (otherwise they double-count as phantom packages).
        # Also skip the leading metadata banner.
        sys_upgradable=$(printf '%s\n' "$dnf_raw" \
          | awk '
              /^Obsoleting/ { stop=1 }
              stop { next }
              NF>=3 && $1 ~ /\./ && $1 !~ /^(Last|Security|Installing)/ {
                n=$1; sub(/\.[^.]*$/, "", n); printf "%s\t%s\n", n, $2 }' \
          | jq -Rsc 'split("\n") | map(select(length>0) | split("\t")
                     | {name:.[0], from:"", to:(.[1]//"")})')
      fi
      ;;
    pacman)
      if command -v pacman >/dev/null 2>&1; then
        sys_installed=true
        local pac_raw
        pac_raw=$(pacman -Qu 2>/dev/null || true)
        if [ -n "$pac_raw" ]; then
          # "name oldver -> newver"
          sys_upgradable=$(printf '%s\n' "$pac_raw" \
            | awk 'NF>=4 { printf "%s\t%s\t%s\n", $1, $2, $4 }' \
            | jq -Rsc 'split("\n") | map(select(length>0) | split("\t")
                       | {name:.[0], from:(.[1]//""), to:(.[2]//"")})')
        fi
      fi
      ;;
    *) ;;  # unknown manager → sys_installed stays false
  esac
  sys_count=$(jq 'length' <<<"$sys_upgradable")

  # ── snap (user-scoped, auto-appliable) ──
  if command -v snap >/dev/null 2>&1; then
    snap_installed=true
    local snap_raw
    snap_raw=$(snap refresh --list 2>/dev/null || true)
    # Drop the header row and the "All snaps up to date." sentinel.
    snap_refreshable=$(printf '%s\n' "$snap_raw" \
      | awk 'NR>1 && $0 !~ /All snaps up to date/ && NF>=1 { print $1 }' \
      | jq -Rsc 'split("\n") | map(select(length>0) | {name:.})')
  fi

  # ── flatpak (user-scoped, auto-appliable) ──
  # `--columns=application` returns the stable app ID (e.g. org.gimp.GIMP),
  # one per line. Without it, the default first column is the human display
  # name ("GNU Image Manipulation Program"), which is unstable and may
  # contain spaces. App ID is what the user recognises and what flatpak acts on.
  if command -v flatpak >/dev/null 2>&1; then
    flatpak_installed=true
    local fp_raw
    fp_raw=$(flatpak remote-ls --updates --columns=application 2>/dev/null || true)
    flatpak_updatable=$(printf '%s\n' "$fp_raw" \
      | awk 'NF>=1 && length($1)>0 { print $1 }' \
      | jq -Rsc 'split("\n") | map(select(length>0) | {name:.})')
  fi

  # ── Windows package managers (WSL2 only — audit only, never run) ──
  local win_json='{"wsl2":false,"mnt_c":false,"managers":[]}'
  if [ "$OS_TYPE" = "wsl2" ]; then
    local mnt_c=false win_mgrs='[]'
    [ -d /mnt/c ] && mnt_c=true
    local m
    # WSL interop exposes Windows executables WITH the .exe extension
    # (`winget.exe`), not bare `winget`, so probe both forms and report the
    # canonical name once if either resolves.
    for m in winget scoop choco; do
      if command -v "$m" >/dev/null 2>&1 || command -v "$m.exe" >/dev/null 2>&1; then
        win_mgrs=$(jq --arg n "$m" '. + [$n]' <<<"$win_mgrs")
      fi
    done
    win_json=$(jq -n --argjson wsl2 true --argjson mnt_c "$mnt_c" \
      --argjson mgrs "$win_mgrs" '{wsl2:$wsl2, mnt_c:$mnt_c, managers:$mgrs}')
  fi

  jq -n \
    --arg manager "$manager" \
    --argjson sys_installed "$sys_installed" \
    --argjson sys_upgradable "$sys_upgradable" \
    --argjson sys_count "$sys_count" \
    --argjson snap_installed "$snap_installed" \
    --argjson snap_refreshable "$snap_refreshable" \
    --argjson flatpak_installed "$flatpak_installed" \
    --argjson flatpak_updatable "$flatpak_updatable" \
    --argjson windows "$win_json" \
    --argjson errors "$errors" \
    '{system:{manager:$manager, installed:$sys_installed,
              upgradable:$sys_upgradable, count:$sys_count, requires_sudo:true},
      snap:{installed:$snap_installed, refreshable:$snap_refreshable},
      flatpak:{installed:$flatpak_installed, updatable:$flatpak_updatable},
      windows:$windows,
      errors:$errors}'
}

# ── Language section ─────────────────────────────────────────────
discover_language() {
  # npm globals
  local npm_installed=false npm_outdated='[]'
  if command -v npm >/dev/null 2>&1; then
    npm_installed=true
    local npm_raw
    npm_raw=$(npm outdated -g --json 2>/dev/null || echo '{}')
    npm_outdated=$(jq -c 'to_entries | map({
      name: .key,
      from: (.value.current // ""),
      to: (.value.latest // ""),
      bump: "patch"
    })' <<<"$npm_raw" 2>/dev/null || echo '[]')
    # Re-classify bump
    npm_outdated=$(jq -c --slurp 'add // []' < <(jq -c '.[]' <<<"$npm_outdated" 2>/dev/null) 2>/dev/null || echo "$npm_outdated")
    # Bump classification per entry (re-do in jq using semver delta)
    npm_outdated=$(jq -c '[.[] | . + {bump: (
      (.from | split(".") | (.[0]//"0") | tostring) as $fm |
      (.to   | split(".") | (.[0]//"0") | tostring) as $tm |
      (.from | split(".") | (.[1]//"0") | tostring) as $fn |
      (.to   | split(".") | (.[1]//"0") | tostring) as $tn |
      if $fm != $tm then "major"
      elif $fn != $tn then "minor"
      else "patch" end
    )}]' <<<"$npm_outdated" 2>/dev/null || echo "$npm_outdated")
  fi

  # pipx
  local pipx_installed=false pipx_tools='[]' pipx_outdated_count=0
  if command -v pipx >/dev/null 2>&1; then
    pipx_installed=true
    local pipx_raw
    pipx_raw=$(pipx list --short 2>/dev/null | awk '{print $1}')
    if [ -n "$pipx_raw" ]; then
      pipx_tools=$(echo "$pipx_raw" | jq -Rsc 'split("\n") | map(select(length > 0))')
      pipx_outdated_count=$(echo "$pipx_raw" | wc -l | tr -d ' ')
    fi
  fi

  # gems (system Ruby detection)
  local gems_installed=false system_ruby=false ruby_version="" gems_outdated='[]'
  if command -v gem >/dev/null 2>&1; then
    gems_installed=true
    local ruby_path ruby_ver_str
    ruby_path=$(command -v ruby 2>/dev/null || echo "")
    ruby_ver_str=$(ruby --version 2>/dev/null || echo "")
    if [ "$ruby_path" = "/usr/bin/ruby" ] && echo "$ruby_ver_str" | grep -q "^ruby 2\."; then
      system_ruby=true
      ruby_version=$(echo "$ruby_ver_str" | awk '{print $2}' | cut -d. -f1-2)
    fi

    local gem_raw
    gem_raw=$(gem outdated 2>/dev/null)
    if [ -n "$gem_raw" ]; then
      while IFS= read -r line; do
        # Format: "name (from < to)"
        local g_name g_from g_to g_bump
        g_name=$(echo "$line" | awk '{print $1}')
        g_from=$(echo "$line" | sed -E 's/.*\(([^[:space:]]+) < ([^)]+)\)/\1/')
        g_to=$(echo "$line"   | sed -E 's/.*\(([^[:space:]]+) < ([^)]+)\)/\2/')
        [ -z "$g_name" ] && continue
        g_bump=$(_bump_class "$g_from" "$g_to")
        gems_outdated=$(jq --arg name "$g_name" --arg from "$g_from" --arg to "$g_to" --arg bump "$g_bump" \
          '. + [{name:$name, from:$from, to:$to, bump:$bump}]' <<<"$gems_outdated")
      done <<<"$gem_raw"
    fi
  fi

  # uv (always offer self-update if installed)
  local uv_installed=false uv_current=""
  if command -v uv >/dev/null 2>&1; then
    uv_installed=true
    uv_current=$(uv --version 2>/dev/null | awk '{print $2}')
  fi

  # bun
  local bun_installed=false bun_current=""
  if command -v bun >/dev/null 2>&1; then
    bun_installed=true
    bun_current=$(bun --version 2>/dev/null)
  fi

  # deno
  local deno_installed=false deno_current=""
  if command -v deno >/dev/null 2>&1; then
    deno_installed=true
    deno_current=$(deno --version 2>/dev/null | head -1 | awk '{print $2}')
  fi

  # rustup, cargo, mise — presence only
  local rustup_installed=false cargo_update_installed=false mise_installed=false
  command -v rustup >/dev/null 2>&1 && rustup_installed=true
  command -v cargo  >/dev/null 2>&1 && cargo install-update --version >/dev/null 2>&1 && cargo_update_installed=true
  command -v mise   >/dev/null 2>&1 && mise_installed=true

  jq -n \
    --argjson npm_installed "$npm_installed" \
    --argjson npm_outdated "$npm_outdated" \
    --argjson pipx_installed "$pipx_installed" \
    --argjson pipx_tools "$pipx_tools" \
    --argjson pipx_outdated_count "$pipx_outdated_count" \
    --argjson gems_installed "$gems_installed" \
    --argjson system_ruby "$system_ruby" \
    --arg ruby_version "$ruby_version" \
    --argjson gems_outdated "$gems_outdated" \
    --argjson uv_installed "$uv_installed" \
    --arg uv_current "$uv_current" \
    --argjson bun_installed "$bun_installed" \
    --arg bun_current "$bun_current" \
    --argjson deno_installed "$deno_installed" \
    --arg deno_current "$deno_current" \
    --argjson rustup_installed "$rustup_installed" \
    --argjson cargo_update_installed "$cargo_update_installed" \
    --argjson mise_installed "$mise_installed" \
    '{npm: {installed:$npm_installed, outdated:$npm_outdated},
      pipx:{installed:$pipx_installed, tools:$pipx_tools, outdated_count:$pipx_outdated_count},
      gems:{installed:$gems_installed, system_ruby:$system_ruby, ruby_version:$ruby_version, outdated:$gems_outdated},
      uv:  {installed:$uv_installed, current:$uv_current},
      bun: {installed:$bun_installed, current:$bun_current},
      deno:{installed:$deno_installed, current:$deno_current},
      rustup:{installed:$rustup_installed},
      cargo:{installed:$cargo_update_installed},
      mise:{installed:$mise_installed},
      errors:[]}'
}

# ── Shadow section (PATH duplicates + broken symlinks) ───────────
discover_shadow() {
  local prefix shadow_json broken_json
  prefix=$(brew --prefix 2>/dev/null || echo "")
  if [ -z "$prefix" ] || [ ! -d "$prefix/bin" ]; then
    jq -n '{duplicates:[], broken_symlinks:[], errors:["brew prefix unavailable"]}'
    return
  fi

  # Single-pass PATH walk. Records first occurrence of each binary
  # across $PATH directories; emits a row when the brew prefix appears
  # AFTER another dir already claimed that name.
  #
  # v1.5.1: replaces the prior awk implementation that built shell
  # commands via string concatenation (`cmd = "ls -1 " P[i] ...`) — a
  # hostile $PATH entry containing `;`, backticks, `$()`, or newlines
  # would have executed arbitrary shell during discovery (codex P1).
  # The bash loop below never invokes a shell with user data; `for f
  # in "$dir"/*` uses bash's own glob, which does not interpret
  # metacharacters from $dir's value.
  # v1.5.1 (codex P1): two-stage PATH walk.
  # Stage 1 (bash): iterate $PATH safely, emit (dir,name) TSV. The bash
  #   for-loop never invokes `sh -c` with user data — it uses bash's own
  #   glob expansion, which treats $PATH segments as paths not commands.
  #   The prior awk implementation built shell strings via concatenation
  #   (`cmd = "ls -1 " P[i] " 2>/dev/null"`) and ran them through awk's
  #   pipe-to-shell — a hostile $PATH entry containing `;`, backticks,
  #   `$()`, or newlines would have executed arbitrary shell.
  # Stage 2 (awk): aggregate the (dir,name) stream with awk's assoc
  #   arrays. macOS ships bash 3.2 which has no `declare -A`, so we
  #   can't keep the aggregation in pure bash without a regression.
  #   awk receives only TSV data — never builds shell commands.
  shadow_input=$(
    IFS=':' read -r -a _path_dirs <<<"$PATH"
    shopt -s nullglob
    for _d in "${_path_dirs[@]}"; do
      [ -z "$_d" ] && continue
      [ -d "$_d" ] || continue
      # Skip CWD-relative entries (don't trust `.` or `./*` in $PATH).
      if [ "${_d:0:1}" = "." ]; then
        if [ "$_d" = "." ] || [ "${_d:0:2}" = "./" ]; then
          continue
        fi
      fi
      for _f in "$_d"/*; do
        _name=${_f##*/}
        printf '%s\t%s\n' "$_d" "$_name"
      done
    done
    shopt -u nullglob
  )
  shadow_tsv=$(printf '%s\n' "$shadow_input" | awk -F'\t' -v prefix="$prefix/bin" '
    NF != 2 { next }
    # Drop rows whose name (col 2) contains control bytes — defends jq
    # downstream from a binary name carrying a tab/newline/escape.
    $2 ~ /[\001-\037\177]/ { next }
    {
      d = $1; name = $2
      if (!(name in seen)) {
        seen[name] = d
      } else if (d == prefix && seen[name] != prefix) {
        print name "\t" seen[name] "\t" prefix
      }
    }
  ')
  shadow_json=$(printf '%s' "$shadow_tsv" \
    | jq -Rsc 'split("\n") | map(select(length > 0) | split("\t") |
       {binary: .[0], primary: .[1], shadowed: [.[2]]})')
  [ -z "$shadow_json" ] && shadow_json='[]'

  broken_json=$(find -L "$prefix/bin" -maxdepth 1 -type l ! -exec test -e {} \; -print 2>/dev/null \
    | head -10 | jq -Rsc 'split("\n") | map(select(length > 0))')
  [ -z "$broken_json" ] && broken_json='[]'

  jq -n --argjson dup "$shadow_json" --argjson broken "$broken_json" \
    '{duplicates:$dup, broken_symlinks:$broken, errors:[]}'
}

# ── Run all sections in parallel ─────────────────────────────────
# Native is the long pole (`brew update` is ~14s on macOS). Running the
# sections concurrently bounds wall time to that pole instead of summing.
#
# v1.6: the native function is OS-selected. discover_shadow's PATH-vs-brew
# duplicate detection is anchored on `brew --prefix`, so it only runs on
# macOS; on Linux/WSL2 shadow is emitted empty (Linux PATH-shadow detection
# is out of scope for v1.6).
TMPDIR_DISCOVER=$(mktemp -d)
trap 'rm -rf -- "$TMPDIR_DISCOVER"' EXIT

echo "discover: starting parallel sections ($OS_TYPE)..." >&2
discover_skills   > "$TMPDIR_DISCOVER/skills.json"   2>"$TMPDIR_DISCOVER/skills.err"   &
PID_SKILLS=$!
discover_language > "$TMPDIR_DISCOVER/language.json" 2>"$TMPDIR_DISCOVER/language.err" &
PID_LANG=$!

case "$OS_TYPE" in
  linux|wsl2)
    discover_native_linux > "$TMPDIR_DISCOVER/native.json" 2>"$TMPDIR_DISCOVER/native.err" &
    PID_NATIVE=$!
    # No brew prefix on Linux → shadow is empty (not run).
    printf '%s\n' '{"duplicates":[],"broken_symlinks":[],"errors":[]}' > "$TMPDIR_DISCOVER/shadow.json"
    PID_SHADOW=""
    ;;
  *)
    discover_native > "$TMPDIR_DISCOVER/native.json" 2>"$TMPDIR_DISCOVER/native.err" &
    PID_NATIVE=$!
    discover_shadow > "$TMPDIR_DISCOVER/shadow.json" 2>"$TMPDIR_DISCOVER/shadow.err" &
    PID_SHADOW=$!
    ;;
esac

wait "$PID_SKILLS" "$PID_NATIVE" "$PID_LANG"
[ -n "$PID_SHADOW" ] && wait "$PID_SHADOW"

SKILLS_JSON=$(cat "$TMPDIR_DISCOVER/skills.json")
NATIVE_JSON=$(cat "$TMPDIR_DISCOVER/native.json")
LANGUAGE_JSON=$(cat "$TMPDIR_DISCOVER/language.json")
SHADOW_JSON=$(cat "$TMPDIR_DISCOVER/shadow.json")

# Fall back to empty JSON sub-objects if any worker died mid-run; the
# downstream synthesizer treats missing arrays as zero-items. The native
# fallback shape matches the OS so synthesize.sh's branch reads the right keys.
[ -z "$SKILLS_JSON" ]   && SKILLS_JSON='{"git_repos":[],"managed":[],"info":{"claude_plugins":0,"codex_skills_total":0,"codex_skills_git":0},"errors":["skills section failed"]}'
case "$OS_TYPE" in
  linux|wsl2)
    [ -z "$NATIVE_JSON" ] && NATIVE_JSON='{"system":{"manager":"unknown","installed":false,"upgradable":[],"count":0,"requires_sudo":true},"snap":{"installed":false,"refreshable":[]},"flatpak":{"installed":false,"updatable":[]},"windows":{"wsl2":false,"mnt_c":false,"managers":[]},"errors":["native section failed"]}'
    ;;
  *)
    [ -z "$NATIVE_JSON" ] && NATIVE_JSON='{"brew":{"installed":false,"outdated":[]},"mas":{"installed":false,"outdated":[]},"softwareupdate":{"installed":false,"updates":[],"restart_required":false},"errors":["native section failed"]}'
    ;;
esac
[ -z "$LANGUAGE_JSON" ] && LANGUAGE_JSON='{"npm":{"installed":false,"outdated":[]},"pipx":{"installed":false,"tools":[],"outdated_count":0},"gems":{"installed":false,"system_ruby":false,"ruby_version":"","outdated":[]},"uv":{"installed":false,"current":""},"bun":{"installed":false,"current":""},"deno":{"installed":false,"current":""},"rustup":{"installed":false},"cargo":{"installed":false},"mise":{"installed":false},"errors":["language section failed"]}'
[ -z "$SHADOW_JSON" ]   && SHADOW_JSON='{"duplicates":[],"broken_symlinks":[],"errors":["shadow section failed"]}'

jq -n \
  --arg arch "$ARCH" \
  --arg os_type "$OS_TYPE" \
  --arg os_distro "${OS_DISTRO:-unknown}" \
  --arg pkg_mgr "${PKG_MGR:-unknown}" \
  --argjson skills "$SKILLS_JSON" \
  --argjson native "$NATIVE_JSON" \
  --argjson language "$LANGUAGE_JSON" \
  --argjson shadow "$SHADOW_JSON" \
  --argjson disk "$disk_json" \
  '{schema_version:"1",
    os:{type:$os_type, distro:$os_distro, pkg_mgr:$pkg_mgr, arch:$arch},
    skills:$skills,
    native:$native,
    language:$language,
    shadow:$shadow,
    disk:$disk}'
