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
    # `.+` not `[^.]+`: a header check like "checking for zlib.h... no" contains
    # a dot in the name, which `[^.]+` can't cross — so the very case we most need
    # (missing header) failed to match and extracted nothing. Anchor on the literal
    # " ... no" suffix and strip it.
    missing=$(echo "$excerpt" | grep -oE "checking for .+\.\.\. no" | head -3 | sed 's/^checking for //; s/\.\.\. no$//' | jq -R '.' | jq -s -c '.')
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

  # ── Pattern 9: dpkg/apt lock held (Linux) ─────────────────────
  elif echo "$excerpt" | grep -qE "Could not get lock /var/lib/(dpkg|apt)|dpkg.*frontend.*lock|E: Unable to (acquire|lock)"; then
    root_cause="apt/dpkg lock held — another package operation is running"
    severity="medium"
    fix_options='[
      {"label":"Find the process holding the lock",
       "command":"sudo lsof /var/lib/dpkg/lock-frontend",
       "risk":"low",
       "rationale":"unattended-upgrades or another apt/dpkg run usually holds it. Wait for it to finish, then retry."},
      {"label":"Wait and retry the upgrade",
       "command":"sudo apt-get upgrade -y",
       "risk":"low",
       "rationale":"The lock clears on its own when the in-progress operation completes."}
    ]'

  # ── Pattern 10: dnf metadata / file conflict (Linux) ──────────
  elif echo "$excerpt" | grep -qE "Failed to synchronize cache|Error: Transaction (test |)failed|file conflicts|conflicting requests|Problem: package"; then
    root_cause="dnf transaction failed — stale metadata or package conflict"
    severity="medium"
    fix_options='[
      {"label":"Refresh dnf metadata and retry",
       "command":"sudo dnf clean all && sudo dnf upgrade -y",
       "risk":"low",
       "rationale":"Clears the cached repodata that caused the sync/transaction failure."},
      {"label":"Inspect the conflicting packages",
       "command":"dnf repoquery --conflicts <package-name>",
       "risk":"low",
       "rationale":"Shows what the failing package conflicts with so you can resolve it."}
    ]'

  # ── Pattern 11: snap change in progress / held (Linux) ────────
  elif [ "$tool" = "snap" ] && \
       echo "$excerpt" | grep -qE "change in progress|snap .* has running apps|too early for operation|cannot refresh.*held"; then
    root_cause="snap refresh blocked — a snap change is in progress or held"
    severity="medium"
    fix_options='[
      {"label":"List in-progress snap changes",
       "command":"snap changes",
       "risk":"low",
       "rationale":"Shows the running change; wait for it to reach Done, then retry snap refresh."},
      {"label":"Retry a single snap once the change clears",
       "command":"snap refresh <snap-name>",
       "risk":"low",
       "rationale":"Targets just the blocked snap instead of the whole set."}
    ]'

  # ── Pattern 12: flatpak runtime missing (Linux) ───────────────
  elif [ "$tool" = "flatpak" ] && \
       echo "$excerpt" | grep -qE "runtime/[^ ]+ not installed|Required runtime .* not installed|No such ref"; then
    local rt
    rt=$(echo "$excerpt" | grep -oE "runtime/[^ ]+" | head -3 | jq -R '.' | jq -s -c '.')
    rt=${rt:-'[]'}
    root_cause="flatpak update failed — a required runtime is not installed"
    severity="medium"
    failing_items="$rt"
    fix_options='[
      {"label":"Install missing runtimes from flathub",
       "command":"flatpak install flathub <runtime-id>",
       "risk":"low",
       "rationale":"The app needs a runtime that is not present. Install it, then re-run the update."},
      {"label":"Update and prune unused runtimes",
       "command":"flatpak update && flatpak uninstall --unused",
       "risk":"low",
       "rationale":"Reconciles the runtime set the installed apps expect."}
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

# v1.5.1 (codex P2): validate every TSV row before processing.
# - tool must be in the v1.5 allowlist; reject anything else
# - rc must be numeric
# - kind must be "hard" or "partial"
# - log_path must be an absolute path with no shell metacharacters or
#   path-traversal segments, and must resolve under a known temp/data dir
_TSV_ALLOWED_TOOLS=" skills brew npm pipx gems uv bun mas macos snap flatpak "
while IFS=$'\t' read -r tool rc kind log_path; do
  [ -z "${tool:-}" ] && continue

  case " $_TSV_ALLOWED_TOOLS " in
    *" $tool "*) ;;
    *)
      errors=$(jq --arg t "${tool:0:64}" \
        '. + ["rejecting unknown tool id in failure log: \($t)"]' <<<"$errors")
      continue
      ;;
  esac
  case "$rc" in
    ''|*[!0-9]*)
      errors=$(jq --arg r "${rc:0:32}" \
        '. + ["rejecting non-numeric rc: \($r)"]' <<<"$errors")
      continue
      ;;
  esac
  case "$kind" in
    hard|partial) ;;
    *)
      errors=$(jq --arg k "${kind:0:32}" \
        '. + ["rejecting unknown kind: \($k)"]' <<<"$errors")
      continue
      ;;
  esac
  case "$log_path" in
    /*) ;;
    *)
      errors=$(jq '. + ["rejecting non-absolute log path"]' <<<"$errors")
      continue
      ;;
  esac
  case "$log_path" in
    *..*|*$'\n'*|*$'\r'*|*$'\t'*|*'`'*|*'$('*|*';'*)
      errors=$(jq '. + ["rejecting log path with suspicious chars"]' <<<"$errors")
      continue
      ;;
  esac
  if [ ! -f "$log_path" ]; then
    errors=$(jq --arg t "$tool" --arg p "${log_path:0:200}" \
      '. + ["log not found for \($t): \($p)"]' <<<"$errors")
    continue
  fi
  one=$(_diagnose_one "$tool" "$rc" "$kind" "$log_path")
  diagnoses=$(jq --argjson d "$one" '. + [$d]' <<<"$diagnoses")
done

# Defense-in-depth: strip destructive commands defensively. Even though
# the pattern table is hand-authored, this matches the v1.4 invariant —
# no fix_option command may contain rm -rf, sudo rm, --force, etc.
#
# v1.5.1 (codex P2): broaden the regex. The prior version missed:
#   - standalone `sh ...` or `bash ...` invocations
#   - `curl ... | sh` without spaces around the pipe
#   - `bash <(curl ...)` process substitution
#   - `eval`, `exec`, `source`, `.` shorthand
#   - kill -9, dd of=, write to /dev/sd*
# This is still a denylist — false negatives possible. The pattern table
# is hand-authored so any false negative would have to be authored in.
diagnoses=$(jq '
  map(
    .fix_options |= map(select(
      (.command | test(
        "rm[[:space:]]+-[a-z]*r[a-z]*f|rm[[:space:]]+-[a-z]*f[a-z]*r|rm[[:space:]]+-r[[:space:]]+-f|rm[[:space:]]+-f[[:space:]]+-r|--no-verify|--force|push[[:space:]]+--force|chmod[[:space:]]+777|sudo[[:space:]]+rm|curl[^|]*\\|[[:space:]]*(sh|bash|zsh)|wget[^|]*\\|[[:space:]]*(sh|bash|zsh)|bash[[:space:]]*<\\([[:space:]]*curl|sh[[:space:]]*<\\([[:space:]]*curl|^[[:space:]]*(sh|bash|zsh|eval|exec|source|\\.)[[:space:]]|;[[:space:]]*(sh|bash|zsh|eval|rm|kill)[[:space:]]|&&[[:space:]]*(rm|kill|chmod[[:space:]]+777)|dd[[:space:]]+.*of=/dev|>[[:space:]]*/dev/(sd|nvme|disk)"
        ; "i"
      )) | not
    ))
  )
' <<<"$diagnoses" 2>/dev/null || echo '[]')
# Fail CLOSED: if the denylist filter ever errors, emit no diagnoses rather than
# the prior `|| echo "$diagnoses"`, which fell back to the UNFILTERED list and
# would have surfaced exactly the destructive commands the filter exists to strip.

jq -n --argjson d "$diagnoses" --argjson e "$errors" \
  '{diagnoses:$d, errors:$e}'
