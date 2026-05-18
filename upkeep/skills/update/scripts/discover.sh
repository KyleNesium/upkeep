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
SCOUT_MAX_REPOS="${UPKEEP_MAX_REPOS:-200}"

if ! command -v jq >/dev/null 2>&1; then
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

# Detect arch
ARCH=$(uname -m 2>/dev/null || echo unknown)

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
        git -C "$path" fetch --tags -q origin 2>/dev/null
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

  # ── Plugin-cache-managed plugins ──
  if [ -d "$PLUGIN_CACHE_ROOT" ]; then
    local owner_dir plugin_dir version_dir plugin_json name version
    for owner_dir in "$PLUGIN_CACHE_ROOT"/*/; do
      [ -d "$owner_dir" ] || continue
      for plugin_dir in "$owner_dir"*/; do
        [ -d "$plugin_dir" ] || continue
        # Find the most-recent version directory under the plugin
        version_dir=$(find "$plugin_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
          | sort -V | tail -1)
        [ -z "$version_dir" ] && version_dir="$plugin_dir"
        plugin_json="$version_dir/.claude-plugin/plugin.json"
        [ -f "$plugin_json" ] || continue
        name=$(jq -r '.name // empty' "$plugin_json" 2>/dev/null)
        version=$(jq -r '.version // "unknown"' "$plugin_json" 2>/dev/null)
        [ -z "$name" ] && name=$(basename "$plugin_dir")
        managed=$(jq --arg name "$name" --arg version "$version" \
          '. + [{name:$name, manager:"claude-code-plugin", version:$version,
                update_command:("/plugin update " + $name)}]' <<<"$managed")
        claude_plugins_count=$((claude_plugins_count + 1))
      done
    done
  fi

  # Counts
  if [ -d "$CODEX_SKILLS_ROOT" ]; then
    codex_total=$(find "$CODEX_SKILLS_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  fi

  jq -n \
    --argjson git_repos "$git_repos" \
    --argjson managed "$managed" \
    --argjson claude_plugins "$claude_plugins_count" \
    --argjson codex_total "$codex_total" \
    --argjson codex_git "$codex_git" \
    '{git_repos:$git_repos, managed:$managed,
      info:{claude_plugins:$claude_plugins, codex_skills_total:$codex_total, codex_skills_git:$codex_git},
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
    brew update >/dev/null 2>&1 || errors=$(jq '. + ["brew update failed"]' <<<"$errors")

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

  # Single-pass PATH walk. The shell printed each shadow as a TSV row;
  # awk reads each PATH dir, records first occurrence of each binary,
  # then emits a row when the brew prefix is encountered AFTER another dir
  # contained the same name.
  shadow_json=$(awk -v prefix="$prefix/bin" 'BEGIN {
    n = split(ENVIRON["PATH"], P, ":")
    for (i = 1; i <= n; i++) {
      cmd = "ls -1 " P[i] " 2>/dev/null"
      while ((cmd | getline name) > 0) {
        if (!(name in seen)) seen[name] = P[i]
        else if (P[i] == prefix && seen[name] != prefix) {
          print name "\t" seen[name] "\t" prefix
        }
      }
      close(cmd)
    }
  }' | jq -Rsc 'split("\n") | map(select(length > 0) | split("\t") |
       {binary: .[0], primary: .[1], shadowed: [.[2]]})')
  [ -z "$shadow_json" ] && shadow_json='[]'

  broken_json=$(find -L "$prefix/bin" -maxdepth 1 -type l ! -exec test -e {} \; -print 2>/dev/null \
    | head -10 | jq -Rsc 'split("\n") | map(select(length > 0))')
  [ -z "$broken_json" ] && broken_json='[]'

  jq -n --argjson dup "$shadow_json" --argjson broken "$broken_json" \
    '{duplicates:$dup, broken_symlinks:$broken, errors:[]}'
}

# ── Run all sections in parallel ─────────────────────────────────
# Native is the long pole (`brew update` is ~14s). Running the four sections
# concurrently bounds wall time to that pole instead of summing all four.
TMPDIR_DISCOVER=$(mktemp -d)
trap 'rm -rf -- "$TMPDIR_DISCOVER"' EXIT

echo "discover: starting 4 parallel sections..." >&2
discover_skills   > "$TMPDIR_DISCOVER/skills.json"   2>"$TMPDIR_DISCOVER/skills.err"   &
PID_SKILLS=$!
discover_native   > "$TMPDIR_DISCOVER/native.json"   2>"$TMPDIR_DISCOVER/native.err"   &
PID_NATIVE=$!
discover_language > "$TMPDIR_DISCOVER/language.json" 2>"$TMPDIR_DISCOVER/language.err" &
PID_LANG=$!
discover_shadow   > "$TMPDIR_DISCOVER/shadow.json"   2>"$TMPDIR_DISCOVER/shadow.err"   &
PID_SHADOW=$!

wait "$PID_SKILLS" "$PID_NATIVE" "$PID_LANG" "$PID_SHADOW"

SKILLS_JSON=$(cat "$TMPDIR_DISCOVER/skills.json")
NATIVE_JSON=$(cat "$TMPDIR_DISCOVER/native.json")
LANGUAGE_JSON=$(cat "$TMPDIR_DISCOVER/language.json")
SHADOW_JSON=$(cat "$TMPDIR_DISCOVER/shadow.json")

# Fall back to empty JSON sub-objects if any worker died mid-run; the
# downstream synthesizer treats missing arrays as zero-items.
[ -z "$SKILLS_JSON" ]   && SKILLS_JSON='{"git_repos":[],"managed":[],"info":{"claude_plugins":0,"codex_skills_total":0,"codex_skills_git":0},"errors":["skills section failed"]}'
[ -z "$NATIVE_JSON" ]   && NATIVE_JSON='{"brew":{"installed":false,"outdated":[]},"mas":{"installed":false,"outdated":[]},"softwareupdate":{"installed":false,"updates":[],"restart_required":false},"errors":["native section failed"]}'
[ -z "$LANGUAGE_JSON" ] && LANGUAGE_JSON='{"npm":{"installed":false,"outdated":[]},"pipx":{"installed":false,"tools":[],"outdated_count":0},"gems":{"installed":false,"system_ruby":false,"ruby_version":"","outdated":[]},"uv":{"installed":false,"current":""},"bun":{"installed":false,"current":""},"deno":{"installed":false,"current":""},"rustup":{"installed":false},"cargo":{"installed":false},"mise":{"installed":false},"errors":["language section failed"]}'
[ -z "$SHADOW_JSON" ]   && SHADOW_JSON='{"duplicates":[],"broken_symlinks":[],"errors":["shadow section failed"]}'

jq -n \
  --arg arch "$ARCH" \
  --argjson skills "$SKILLS_JSON" \
  --argjson native "$NATIVE_JSON" \
  --argjson language "$LANGUAGE_JSON" \
  --argjson shadow "$SHADOW_JSON" \
  --argjson disk "$disk_json" \
  '{schema_version:"1",
    os:{type:"macos", arch:$arch},
    skills:$skills,
    native:$native,
    language:$language,
    shadow:$shadow,
    disk:$disk}'
