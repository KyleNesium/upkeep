#!/usr/bin/env bash
# upkeep failure diagnoser — pattern table (v1.5)
#
# Replaces the v1.3 `failure-diagnoser` LLM agent. ~80% of real-world
# /upkeep:update failures match a small set of well-known patterns
# (system Ruby too old, missing build deps, permission errors, broken
# native modules). A static case-statement is faster, deterministic, and
# easier to extend.
#
# Input (one per line on stdin, tab-separated):
#   <tool>\t<rc>\t<kind>\t<log_path>
#     tool      — brew | npm | pipx | gems | uv | bun | mas | macos
#     rc        — exit code (0 = partial, non-zero = hard failure)
#     kind      — "hard" | "partial"
#     log_path  — absolute path to per-tool apply log
#
# Output (stdout): JSON matching v1.4 failure-diagnoser agent schema:
#   {"diagnoses":[{tool, severity, root_cause, failing_items,
#                  fix_options:[{label, command, risk, rationale}]}],
#    "errors":[]}
#
# Suggested `command` strings are TEXT ONLY — never auto-executed.
# Caller (SKILL.md) surfaces them with a `$` prefix and copy-paste label.

set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo '{"diagnoses":[],"errors":["jq unavailable — diagnosis skipped"]}'
  exit 0
fi

# ── Pattern matcher ──────────────────────────────────────────────
# Each pattern is (tool-filter, regex, root_cause, severity, fix_options_jq).
# fix_options_jq is a JSON array literal — kept compact so the table is
# readable. `severity` maps to the v1.4 rubric: high = tool broken,
# medium = partial coverage, low = cosmetic.
#
# `\$NAME` placeholders in fix_options expand against awk-extracted
# `failing_items` (joined as space-separated). Empty list → placeholder
# rendered as `<name>`.
_diagnose_one() {
  local tool="$1" rc="$2" kind="$3" log_path="$4"
  local excerpt root_cause severity failing_items fix_options

  # Bounded log excerpt: last 200 lines, capped at 16 KB.
  excerpt=$(tail -200 "$log_path" 2>/dev/null | head -c 16000)
  if [ -z "$excerpt" ]; then
    jq -n --arg tool "$tool" \
      '{tool:$tool, severity:"low",
        root_cause:"Log excerpt unavailable",
        failing_items:[],
        fix_options:[{label:"Investigate manually",
                      command:"cat <log_path>",
                      risk:"low",
                      rationale:"No log content captured for this tool."}]}'
    return
  fi

  # Defaults — overridden by first matching pattern.
  root_cause="Failure pattern not in diagnoser table"
  severity="medium"
  failing_items='[]'
  fix_options='[{"label":"Investigate manually",
                 "command":"tail -100 <log_path>",
                 "risk":"low",
                 "rationale":"No known pattern matched the failure. Inspect the apply log for context."}]'

  # ── Pattern 1: system Ruby too old (gems) ────────────────────
  if [ "$tool" = "gems" ] && \
     echo "$excerpt" | grep -qE "requires Ruby version >= [0-9]"; then
    local items
    items=$(echo "$excerpt" | awk '
      /^ERROR:  Error installing/ {
        for (i=1;i<=NF;i++) if ($i ~ /^[a-z0-9_-]+:/) { gsub(":","",$i); print $i }
      }' | sort -u | head -20 | jq -R '.' | jq -s -c '.')
    items=${items:-'[]'}
    root_cause="Some gems require Ruby >= 2.7 but system Ruby is 2.6"
    severity="medium"
    failing_items="$items"
    fix_options='[
      {"label":"Install modern Ruby via mise (recommended)",
       "command":"brew install mise",
       "risk":"low",
       "rationale":"Keeps system Ruby intact. After install: mise use -g ruby@3.3"},
      {"label":"Leave system Ruby pinned and accept partial gem coverage",
       "command":"(no action)",
       "risk":"low",
       "rationale":"Compatible gems remain installed; affected gems stay at older versions"}
    ]'

  # ── Pattern 2: missing build dependency (extconf) ─────────────
  elif echo "$excerpt" | grep -qE "checking for .* no"; then
    local missing
    missing=$(echo "$excerpt" | grep -oE "checking for [^.]+\.\.\. no" | head -3 | sed 's/checking for //; s/\.\.\. no//' | jq -R '.' | jq -s -c '.')
    missing=${missing:-'[]'}
    root_cause="Native extension build failed — missing system library"
    severity="medium"
    failing_items="$missing"
    fix_options='[
      {"label":"Install the missing library via brew (inspect log for exact name)",
       "command":"brew install <lib-name-from-log>",
       "risk":"low",
       "rationale":"extconf could not locate a required C library. brew install usually resolves it."},
      {"label":"Inspect the full mkmf log",
       "command":"find . -name mkmf.log -mmin -10",
       "risk":"low",
       "rationale":"mkmf.log has the exact compiler invocation and error."}
    ]'

  # ── Pattern 3: permission errors (EACCES / rb_sysopen) ────────
  elif echo "$excerpt" | grep -qE "Permission denied|EACCES|rb_sysopen"; then
    root_cause="Permission denied writing to install location"
    severity="medium"
    fix_options='[
      {"label":"Re-run gem update with --user-install",
       "command":"gem update --user-install",
       "risk":"low",
       "rationale":"Installs to ~/.gem instead of the system gem path. No sudo needed."},
      {"label":"Check ownership of the install prefix",
       "command":"ls -la $(gem env gemdir)",
       "risk":"low",
       "rationale":"If the prefix is root-owned, --user-install is the right answer."}
    ]'

  # ── Pattern 4: broken pipx venv (ImportError) ─────────────────
  elif [ "$tool" = "pipx" ] && \
       echo "$excerpt" | grep -qE "ImportError|ModuleNotFoundError"; then
    local pkgs
    pkgs=$(echo "$excerpt" | grep -oE "No module named '[^']+'" | head -5 | sed "s/No module named '//; s/'//" | jq -R '.' | jq -s -c '.')
    pkgs=${pkgs:-'[]'}
    root_cause="pipx venv broken — likely Python interpreter upgrade left tools stranded"
    severity="high"
    failing_items="$pkgs"
    fix_options='[
      {"label":"Reinstall all pipx tools against the current Python",
       "command":"pipx reinstall-all",
       "risk":"medium",
       "rationale":"Rebuilds every pipx venv against the current python3. Slow but reliable."},
      {"label":"Reinstall a single broken tool",
       "command":"pipx reinstall <tool-name>",
       "risk":"low",
       "rationale":"Faster than reinstall-all if only one tool is affected."}
    ]'

  # ── Pattern 5: broken native module (dyld) ────────────────────
  elif echo "$excerpt" | grep -qE "dyld\[.*\]: Library not loaded|dyld: Library not loaded"; then
    root_cause="Native module linked against a brew library that was upgraded"
    severity="high"
    fix_options='[
      {"label":"Reinstall the package against the new library version",
       "command":"<pkg-manager> reinstall <package-name>",
       "risk":"medium",
       "rationale":"The package has a stale linker reference. Reinstall rebuilds the link."},
      {"label":"Check which library is missing",
       "command":"otool -L $(which <binary>)",
       "risk":"low",
       "rationale":"Shows the exact dylib paths the binary expects."}
    ]'

  # ── Pattern 6: architecture mismatch ──────────────────────────
  elif echo "$excerpt" | grep -qE "incompatible cpu-arch|wrong ELF class|mach-o, but built for"; then
    root_cause="Architecture mismatch — binary built for wrong CPU arch"
    severity="high"
    fix_options='[
      {"label":"Reinstall under the matching arch",
       "command":"arch -arm64 <pkg-manager> install <name>",
       "risk":"medium",
       "rationale":"Forces the package manager to fetch/build the native arch."},
      {"label":"Verify your shell arch",
       "command":"uname -m",
       "risk":"low",
       "rationale":"Confirms whether you are in an arm64 or x86_64 shell."}
    ]'

  # ── Pattern 7: version solver constraint ──────────────────────
  elif echo "$excerpt" | grep -qE "no compatible version found|could not find a satisfying|Bundler could not find compatible"; then
    root_cause="Dependency solver could not satisfy version constraints"
    severity="medium"
    fix_options='[
      {"label":"Inspect available versions",
       "command":"<pkg-manager> info <name>",
       "risk":"low",
       "rationale":"Shows the available versions and current constraints."}
    ]'

  # ── Pattern 8: brew formula post-install failure ──────────────
  elif [ "$tool" = "brew" ] && \
       echo "$excerpt" | grep -qE "post_install failed|formulae .* failed to upgrade"; then
    local formulas
    formulas=$(echo "$excerpt" | grep -oE "Error: .* (failed to upgrade|post_install)" | head -5 | jq -R '.' | jq -s -c '.')
    formulas=${formulas:-'[]'}
    root_cause="Brew formula post-install hook failed"
    severity="medium"
    failing_items="$formulas"
    fix_options='[
      {"label":"Retry the failing formula by itself",
       "command":"brew upgrade <formula-name>",
       "risk":"low",
       "rationale":"Other formulas may have left a clean state; single retry often succeeds."},
      {"label":"Read the brew install log",
       "command":"brew log <formula-name>",
       "risk":"low",
       "rationale":"Shows the formula source and recent upstream changes."}
    ]'
  fi

  # Compose final diagnosis. All strings clamped to 280 chars at the
  # end as defense-in-depth against any unbounded log content slipping
  # through awk extraction.
  jq -n \
    --arg tool "$tool" \
    --arg sev "$severity" \
    --arg rc_str "$root_cause" \
    --argjson items "$failing_items" \
    --argjson opts "$fix_options" \
    '{tool:$tool, severity:$sev, root_cause:$rc_str,
      failing_items:$items, fix_options:$opts}
     | walk(if type == "string" then .[0:280] else . end)'
}

# ── Main loop ────────────────────────────────────────────────────
diagnoses='[]'
errors='[]'

while IFS=$'\t' read -r tool rc kind log_path; do
  [ -z "${tool:-}" ] && continue
  if [ ! -f "${log_path:-}" ]; then
    errors=$(jq --arg t "$tool" --arg p "${log_path:-<empty>}" \
      '. + ["log not found for \($t): \($p)"]' <<<"$errors")
    continue
  fi
  one=$(_diagnose_one "$tool" "$rc" "$kind" "$log_path")
  diagnoses=$(jq --argjson d "$one" '. + [$d]' <<<"$diagnoses")
done

# Defense-in-depth: strip destructive commands defensively. Even though
# the pattern table is hand-authored, this matches the v1.4 invariant —
# no fix_option command may contain rm -rf, sudo rm, --force, etc.
diagnoses=$(jq '
  map(
    .fix_options |= map(select(
      (.command | test("rm -rf|--no-verify|--force|push --force|chmod 777|sudo rm|curl .* \\| .*sh"; "i")) | not
    ))
  )
' <<<"$diagnoses" 2>/dev/null || echo "$diagnoses")

jq -n --argjson d "$diagnoses" --argjson e "$errors" \
  '{diagnoses:$d, errors:$e}'
