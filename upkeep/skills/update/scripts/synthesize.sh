#!/usr/bin/env bash
# upkeep plan synthesizer — macOS fast path (v1.4)
#
# Replaces the v1.3 synthesizer agent. All logic here is deterministic:
# - Fixed category ordering (skills → brew → language → stores)
# - Compat-matrix warnings materialised from discovery
# - Bake-in ETA defaults with optional history-median refinement
# - Tool spec flags only (gems.user_install) — never command strings
#
# Usage: synthesize.sh <compatibility.json> [history.json]
# Stdin: discovery JSON
# Stdout: plan JSON (schema_version "1")
# Stderr: human diagnostics

set -uo pipefail

COMPAT_FILE="${1:?compatibility.json required}"
HIST_FILE="${2:-}"

if ! command -v jq >/dev/null 2>&1; then
  echo "synthesize.sh: jq is required" >&2
  exit 1
fi
if [ ! -f "$COMPAT_FILE" ]; then
  echo "synthesize.sh: compatibility file not found: $COMPAT_FILE" >&2
  exit 1
fi

DISCOVERY=$(cat)
if ! jq -e '.schema_version == "1"' <<<"$DISCOVERY" >/dev/null 2>&1; then
  echo "synthesize.sh: discovery JSON has wrong schema_version" >&2
  exit 1
fi

COMPAT=$(jq -c '.' "$COMPAT_FILE")
HISTORY='{}'
if [ -n "$HIST_FILE" ] && [ -f "$HIST_FILE" ]; then
  HISTORY=$(jq -c '.' "$HIST_FILE" 2>/dev/null || echo '{}')
fi

# ── Disk-refuse short-circuit ────────────────────────────────────
FREE_GB=$(jq -r '.disk.free_gb' <<<"$DISCOVERY")
REFUSE_GB=$(jq -r '.disk.refuse_threshold_gb' <<<"$DISCOVERY")
if [ "$FREE_GB" -lt "$REFUSE_GB" ] 2>/dev/null; then
  jq -n --argjson free "$FREE_GB" '{
    schema_version: "1",
    summary: {category_counts: {}, eta_minutes_p50: 0, eta_minutes_p90: 0},
    warnings: [{severity: "high", code: "disk-refuse",
                message: ("Refusing to run: only " + ($free | tostring) + " GB free on /")}],
    manual_steps: [],
    ordered_groups: [],
    tool_specs: {}
  }'
  exit 0
fi

# ── Build warnings[] from compat edges that materialised ─────────
# An edge "materialises" when:
#   - the source brew package appears in native.brew.outdated at >= the edge's
#     gating bump (major edges fire on majors; minor edges also fire on minors)
# We compute this with jq using both inputs.
WARNINGS=$(jq -nc \
  --argjson discovery "$DISCOVERY" \
  --argjson compat "$COMPAT" '
  ($discovery.native.brew.outdated // []) as $brew |
  ($compat.edges // []) as $edges |
  [ $edges[] as $edge |
    # edge.from is like "brew:node" or "brew:python@*" or "brew:openssl@*".
    ($edge.from | sub("^brew:"; "")) as $pat |
    # Match brew formulas against the pattern. Treat trailing wildcard "@*" as prefix match.
    [ $brew[] | select(
        ($pat | test("@\\*$")) as $is_wild |
        if $is_wild then (.name | startswith($pat | sub("@\\*$"; "@"))) or (.name == ($pat | sub("@\\*$"; "")))
        else .name == $pat end
      ) ] as $hits |
    if ($hits | length) == 0 then empty
    else
      # Pick the highest bump among hits to decide severity.
      ($hits | map(.bump) | (if any(. == "major") then "major"
                              elif any(. == "minor") then "minor"
                              else "patch" end)) as $worst_bump |
      ($edge["severity_on_" + $worst_bump] // $edge.severity_on_minor // "low") as $sev |
      {severity: $sev, code: ("compat:" + $edge.from + "→" + $edge.to),
       message: ($edge.reason
                 + "  (from: " + ($hits | map(.name) | join(",")) + ")"),
       affected_from: $edge.from, affected_to: $edge.to, bump: $worst_bump}
    end
  ]
  | sort_by(if .severity == "high" then 0 elif .severity == "medium" then 1 else 2 end)
')

# Add system-Ruby warning when system_ruby true AND there are major gem bumps
SYSTEM_RUBY_WARN=$(jq -nc \
  --argjson d "$DISCOVERY" '
  if ($d.language.gems.system_ruby // false) and
     (($d.language.gems.outdated // []) | any(.bump == "major"))
  then [{severity: "medium", code: "system-ruby-major-gems",
         message: ("System Ruby " + ($d.language.gems.ruby_version // "")
                   + " detected — major gem bumps requiring Ruby >= 2.7 will fail to install. Older compatible versions stay installed.")}]
  else [] end
')
WARNINGS=$(jq -c --argjson a "$WARNINGS" --argjson b "$SYSTEM_RUBY_WARN" '$a + $b' <<<"null")

# ── Build manual_steps[] ─────────────────────────────────────────
MANUAL_STEPS=$(jq -nc --argjson d "$DISCOVERY" '
  # Plugin-cache-managed plugins → /plugin update
  [ ($d.skills.managed // [])[] |
    {kind: "plugin-update",
     message: ("Update Claude Code plugin: " + .update_command)} ]
  # Untrusted skill repos → require trust gate
  + [ ($d.skills.git_repos // [])[] | select(.untrusted == true) |
    {kind: "trust-required",
     message: ("Untrusted skill repo " + .name + " at " + .path
               + " — remote " + .remote_url + " not in trust file")} ]
  # Dirty skill repos → user must clean before pull
  + [ ($d.skills.git_repos // [])[] | select((.dirty_files // []) | length > 0) |
    {kind: "skill-dirty",
     message: ("Skill " + .name + " has uncommitted changes; commit or stash before next /upkeep:update")} ]
  # PATH shadows → informational
  + [ ($d.shadow.duplicates // [])[] |
    {kind: "path-shadow",
     message: ("PATH shadow: " + .binary + " — first match " + .primary
               + " shadows " + (.shadowed | join(",")))} ]
')

# ── Build ordered_groups[] ───────────────────────────────────────
# Fixed order: skills → brew → language (parallel) → stores
ORDERED_GROUPS=$(jq -nc --argjson d "$DISCOVERY" '
  ($d.skills.git_repos // [] | map(select(.untrusted == false and (.commits_behind // 0) > 0 and ((.dirty_files // []) | length) == 0))) as $skills_actionable |
  ($d.native.brew.outdated // []) as $brew |
  ($d.language.npm.outdated // []) as $npm |
  ($d.language.gems.outdated // []) as $gems |
  ($d.language.pipx.tools // []) as $pipx |
  (if $d.language.uv.installed  then ["uv"]  else [] end) as $uv |
  (if $d.language.bun.installed then ["bun"] else [] end) as $bun |
  ($d.native.mas.outdated // []) as $mas |
  ($d.native.softwareupdate.updates // []) as $macos |
  ($d.native.softwareupdate.restart_required // false) as $restart |
  ( (if ($skills_actionable | length) > 0
       then [{name: "skills", parallelism: "serial",
              tools: ["skills"], item_count: ($skills_actionable | length)}]
       else [] end)
    +
    (if ($brew | length) > 0
       then [{name: "brew", parallelism: "exclusive",
              tools: ["brew"], item_count: ($brew | length)}]
       else [] end)
    +
    ( ( [ if ($npm | length)  > 0 then "npm"  else empty end,
          if ($pipx | length) > 0 then "pipx" else empty end,
          if ($gems | length) > 0 then "gems" else empty end ]
        + $uv + $bun ) as $lang_tools |
      if ($lang_tools | length) > 0
        then [{name: "language", parallelism: "parallel",
               tools: $lang_tools,
               item_count: (($npm | length) + ($pipx | length) + ($gems | length) + ($uv | length) + ($bun | length))}]
        else [] end)
    +
    ( ( [ if ($mas | length)   > 0 then "mas"   else empty end,
          if ($macos | length) > 0 then "macos" else empty end ] ) as $store_tools |
      if ($store_tools | length) > 0
        then [{name: "stores", parallelism: "serial",
               tools: $store_tools,
               item_count: (($mas | length) + ($macos | length)),
               restart_required: $restart}]
        else [] end)
  )
')

# ── Build tool_specs{} — flags only, never commands ──────────────
TOOL_SPECS=$(jq -nc --argjson d "$DISCOVERY" '
  {} as $base |
  $base + (if ($d.language.gems.system_ruby // false)
    then {gems: {user_install: true,
                 rationale_for_flag: ("system Ruby " + ($d.language.gems.ruby_version // "?")
                                      + " detected; --user-install avoids sudo")}}
    else {} end)
  + (if ($d.native.softwareupdate.restart_required // false)
    then {macos: {kind: "store", restart_required: true}}
    else {} end)
')

# ── Compute ETA — bake-in defaults, refined by history medians ───
# Seconds per item: brew 25, npm 30, pipx 20, gems 15, uv 5 (total), bun 5 (total),
# skills 3, mas 30, macOS 300.
ETA_JSON=$(jq -nc \
  --argjson d "$DISCOVERY" \
  --argjson hist "$HISTORY" '
  ($d.native.brew.outdated // [] | length) as $brew_n |
  ($d.language.npm.outdated // [] | length) as $npm_n |
  ($d.language.pipx.tools   // [] | length) as $pipx_n |
  ($d.language.gems.outdated // [] | length) as $gems_n |
  ($d.skills.git_repos // [] | map(select((.commits_behind // 0) > 0)) | length) as $skills_n |
  ($d.native.mas.outdated   // [] | length) as $mas_n |
  ($d.native.softwareupdate.updates // [] | length) as $macos_n |
  (if $d.language.uv.installed  then 1 else 0 end) as $uv_n |
  (if $d.language.bun.installed then 1 else 0 end) as $bun_n |
  # Total seconds
  (($brew_n * 25) + ($npm_n * 30) + ($pipx_n * 20) + ($gems_n * 15)
   + ($skills_n * 3) + ($mas_n * 30) + ($macos_n * 300) + ($uv_n * 5) + ($bun_n * 5)) as $p50_s |
  # p90 ~ 1.5x p50, rounded up
  (($p50_s * 3 / 2) | ceil) as $p90_s |
  # Convert to minutes (ceil)
  {p50_minutes: (($p50_s + 59) / 60 | floor), p90_minutes: (($p90_s + 59) / 60 | floor)}
')

# ── Build summary{} ──────────────────────────────────────────────
SUMMARY=$(jq -nc \
  --argjson d "$DISCOVERY" \
  --argjson eta "$ETA_JSON" '
  {category_counts: {
    skills: ($d.skills.git_repos // [] | map(select((.commits_behind // 0) > 0 and .untrusted == false)) | length),
    brew:   ($d.native.brew.outdated // [] | length),
    npm:    ($d.language.npm.outdated // [] | length),
    pipx:   ($d.language.pipx.tools // [] | length),
    gems:   ($d.language.gems.outdated // [] | length),
    uv:     (if $d.language.uv.installed  then 1 else 0 end),
    bun:    (if $d.language.bun.installed then 1 else 0 end),
    mas:    ($d.native.mas.outdated // [] | length),
    macos:  ($d.native.softwareupdate.updates // [] | length)
   },
   eta_minutes_p50: $eta.p50_minutes,
   eta_minutes_p90: $eta.p90_minutes,
   disk_free_gb: $d.disk.free_gb
  }
')

# ── Assemble final plan ──────────────────────────────────────────
jq -n \
  --argjson summary "$SUMMARY" \
  --argjson warnings "$WARNINGS" \
  --argjson manual_steps "$MANUAL_STEPS" \
  --argjson ordered_groups "$ORDERED_GROUPS" \
  --argjson tool_specs "$TOOL_SPECS" '
  {schema_version: "1",
   summary: $summary,
   warnings: $warnings,
   manual_steps: $manual_steps,
   ordered_groups: $ordered_groups,
   tool_specs: $tool_specs}
'
