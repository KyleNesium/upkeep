#!/usr/bin/env bash
# upkeep/clean — single-shot cleanup engine (v1.8)
#
#   clean.sh discover <audit|quick|deep>   → scan, emit manifest + gate JSON
#   clean.sh apply <manifest> [--drop=..] [--items=..]   → (T1, next commit)
#
# Mirrors the update engine's two-turn contract. Targets stock macOS
# /bin/bash 3.2 + BSD userland (no realpath, no timeout, no GNU-only flags).
# The path-safety validator (clean-validate.sh) is the security boundary for
# apply; discover is read-only.

set -uo pipefail

_CLEAN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/common.sh
. "$_CLEAN_DIR/lib/common.sh"
# shellcheck source=clean-validate.sh
. "$_CLEAN_DIR/clean-validate.sh"

DATA_DIR="${UPKEEP_DATA_DIR:-$HOME/.claude/data}"
_detect_os   # sets OS_TYPE / OS_DISTRO / PKG_MGR

_die() { printf '{"error":%s}\n' "$(jq -Rn --arg m "$1" '$m' 2>/dev/null || printf '"%s"' "$1")"; exit 1; }
command -v jq >/dev/null 2>&1 || _die "jq is required"

# ── portable helpers ─────────────────────────────────────────────
# mtime (epoch) — BSD vs GNU stat.
_mtime() {
  if stat -f %m "$1" >/dev/null 2>&1; then stat -f %m "$1" 2>/dev/null
  else stat -c %Y "$1" 2>/dev/null; fi
}
# size in bytes via du -sk (KB on both macOS + Linux) * 1024.
_size_bytes() {
  local kb; kb=$(du -sk "$1" 2>/dev/null | awk '{print $1; exit}')
  [ -n "$kb" ] && printf '%s' "$((kb * 1024))" || printf '0'
}
# ── manifest item accumulation ───────────────────────────────────
# Items accumulate as JSON lines in $ITEMS_FILE; protected skips + warnings +
# manual steps in their own files. _emit handles size/mtime/symlink/dual-repr.
_clean_new_item_ctx() {
  ITEMS_FILE=$(mktemp "${TMPDIR:-/tmp}/upkeep-clean-items.XXXXXX")
  WARN_FILE=$(mktemp "${TMPDIR:-/tmp}/upkeep-clean-warn.XXXXXX")
  SKIP_FILE=$(mktemp "${TMPDIR:-/tmp}/upkeep-clean-skip.XXXXXX")
  MANUAL_FILE=$(mktemp "${TMPDIR:-/tmp}/upkeep-clean-manual.XXXXXX")
  _ITEM_N=0
}
_clean_free_item_ctx() { rm -f -- "$ITEMS_FILE" "$WARN_FILE" "$SKIP_FILE" "$MANUAL_FILE" 2>/dev/null; }

# _emit <category> <path> <action> <safety> [warn_reason] [app_name]
# safety ∈ safe | warn | report_only. path is carried RAW (full fidelity);
# the display field is sanitized for rendering (dual repr, C2 + codex #4).
_emit() {
  local category="$1" path="$2" action="$3" safety="$4" warn="${5:-}" app="${6:-}"
  [ -e "$path" ] || return 0
  _ITEM_N=$((_ITEM_N + 1))
  local size mtime is_sym display
  size=$(_size_bytes "$path")
  mtime=$(_mtime "$path"); mtime=${mtime:-0}
  if [ -L "$path" ]; then is_sym=true; else is_sym=false; fi
  display=$(_sanitize_text "$path")
  jq -nc \
    --arg id "${category}-${_ITEM_N}" --arg category "$category" \
    --arg path "$path" --arg display "$display" \
    --argjson size "$size" --argjson mtime "$mtime" \
    --argjson is_symlink "$is_sym" --arg action "$action" \
    --arg safety "$safety" --arg warn "$warn" --arg app "$app" \
    '{id:$id,category:$category,path:$path,display:$display,size_bytes:$size,
      mtime:$mtime,is_symlink:$is_symlink,action:$action,safety:$safety,
      warn_reason:(if $warn=="" then null else $warn end),
      app_name:(if $app=="" then null else $app end)}' >> "$ITEMS_FILE"
}
_skip_protected() { printf '%s\n' "$1" >> "$SKIP_FILE"; }
_warn()          { printf '%s\n' "$1" >> "$WARN_FILE"; }
_manual()        { printf '%s\n' "$1" >> "$MANUAL_FILE"; }

# Electron leaf basenames (kept in sync with clean-validate.sh).
_electron_leaf_re='Cache|Code Cache|Service Worker|CachedData|CachedExtension|PersistentCache|GPUCache'

# ── scan sections (macOS slice; Linux/WSL2 + remaining phases follow) ──
# Each section honors $MODE: audit reports everything (no truncation);
# quick = subset, build artifacts report_only; deep = full + mutating.

scan_dev_caches() {
  local d
  for d in "$HOME/Library/Caches"/*/ "$HOME/.cache"/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    case "$d" in
      "$HOME/Library/Application Support/Claude"*|"$HOME/.claude"*) _skip_protected "$d"; continue ;;
    esac
    _emit dev_caches "$d" rm safe
  done
}

scan_trash() {
  [ -d "$HOME/.Trash" ] || return 0
  local d
  for d in "$HOME/.Trash"/*; do
    [ -e "$d" ] || continue
    _emit trash "$d" rm safe
  done
}

scan_saved_state() {
  [ "$OS_TYPE" = "macos" ] || return 0
  local d
  for d in "$HOME/Library/Saved Application State"/*/; do
    [ -d "$d" ] || continue
    _emit saved_state "${d%/}" rm safe
  done
}

scan_electron() {
  [ "$OS_TYPE" = "macos" ] || return 0
  local found
  found=$(find "$HOME/Library/Application Support" -maxdepth 5 \
      -not -path "*/Claude/*" -not -path "*/Claude" \
      \( -name "Cache" -o -name "Code Cache" -o -name "Service Worker" \
         -o -name "CachedData" -o -name "CachedExtension*" \
         -o -name "PersistentCache" -o -name "GPUCache" \) \
      -type d 2>/dev/null)
  local d app
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    # app name = the Application Support child dir, for pgrep re-check at apply
    app=$(printf '%s' "$d" | sed "s|$HOME/Library/Application Support/||; s|/.*||")
    _emit electron "$d" electron_cache safe "" "$app"
  done <<EOF
$found
EOF
}

scan_build_artifacts() {
  local roots="" r
  for r in "$HOME/workspace" "$HOME/dev" "$HOME/Developer" "$HOME/code" "$HOME/src" "$HOME/projects" "$HOME/repos"; do
    [ -d "$r" ] && roots="$roots $r"
  done
  [ -n "$roots" ] || return 0
  # build-artifacts: report_only in quick mode (and in audit); rm in deep.
  local action safety
  if [ "$MODE" = "deep" ]; then action=rm; safety=safe; else action=rm; safety=report_only; fi
  local listing tmpf; tmpf=$(mktemp "${TMPDIR:-/tmp}/upkeep-clean-art.XXXXXX")
  if [ "$MODE" = "audit" ]; then
    # audit never truncates (codex #11) — run the find to completion.
    # shellcheck disable=SC2086
    find $roots -maxdepth 4 \( -name node_modules -o -name .venv -o -name venv \
      -o -name .next -o -name dist -o -name build -o -name target \
      -o -name __pycache__ -o -name .pytest_cache -o -name .turbo \) -type d \
      > "$tmpf" 2>/dev/null
  else
    # quick/deep: bash-native wall-clock bound (NO GNU timeout). find runs as
    # a direct bash command in the background; a sleeper kills it on timeout.
    # shellcheck disable=SC2086
    find $roots -maxdepth 4 \( -name node_modules -o -name .venv -o -name venv \
      -o -name .next -o -name dist -o -name build -o -name target \
      -o -name __pycache__ -o -name .pytest_cache -o -name .turbo \) -type d \
      > "$tmpf" 2>/dev/null &
    local fpid=$! kpid
    ( sleep "${UPKEEP_SCAN_BUDGET:-20}"; kill -TERM "$fpid" 2>/dev/null ) & kpid=$!
    if ! wait "$fpid" 2>/dev/null; then
      _warn "build-artifacts scan hit the time budget — results may be partial; re-run for full coverage"
    fi
    kill -TERM "$kpid" 2>/dev/null; wait "$kpid" 2>/dev/null || true
  fi
  listing=$(cat "$tmpf"); rm -f -- "$tmpf"
  local d
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    _emit build_artifacts "$d" "$action" "$safety"
  done <<EOF
$listing
EOF
}

# ── mode → section list ──────────────────────────────────────────
run_sections() {
  case "$MODE" in
    quick)
      scan_dev_caches; scan_electron; scan_trash; scan_build_artifacts ;;
    deep)
      scan_dev_caches; scan_electron; scan_trash; scan_saved_state; scan_build_artifacts ;;
    audit)
      scan_dev_caches; scan_electron; scan_trash; scan_saved_state; scan_build_artifacts ;;
    *) _die "unknown mode: $MODE (want audit|quick|deep)" ;;
  esac
}

# ── manifest assembly + atomic write (update.sh:200 discipline) ───
write_manifest() {
  mkdir -p "$DATA_DIR" 2>/dev/null
  local workdir suffix manifest_file items_json now
  workdir=$(mktemp -d "${DATA_DIR}/.upkeep-clean-tmp.XXXXXX") || _die "mktemp -d failed"
  chmod 700 "$workdir" 2>/dev/null
  suffix=${workdir##*.}
  manifest_file="${DATA_DIR}/upkeep-clean.${suffix}.json"
  now=$(date +%s)
  items_json=$(jq -s '.' "$ITEMS_FILE" 2>/dev/null || echo '[]')
  jq -n --argjson items "$items_json" --arg mode "$MODE" --argjson created_at "$now" \
    '{schema_version:"1", mode:$mode, created_at:$created_at, items:$items}' \
    > "$workdir/m.json" || { rm -rf -- "$workdir"; _die "manifest write failed"; }
  mv -f "$workdir/m.json" "$manifest_file" || { rm -rf -- "$workdir"; _die "manifest rename failed"; }
  rm -rf -- "$workdir"
  printf '%s' "$manifest_file"
}

# SKILL-facing JSON: counts, totals, warnings, manual steps, protected skips.
emit_skill_json() {
  local manifest_file="$1"
  local items_json warns skips manuals
  items_json=$(jq -s '.' "$ITEMS_FILE" 2>/dev/null || echo '[]')
  warns=$(jq -Rs 'split("\n")|map(select(length>0))' "$WARN_FILE" 2>/dev/null || echo '[]')
  skips=$(jq -Rs 'split("\n")|map(select(length>0))' "$SKIP_FILE" 2>/dev/null || echo '[]')
  manuals=$(jq -Rs 'split("\n")|map(select(length>0))' "$MANUAL_FILE" 2>/dev/null || echo '[]')
  local needs_approval=true
  [ "$MODE" = "audit" ] && needs_approval=false
  jq -n \
    --arg manifest_file "$manifest_file" --arg mode "$MODE" --arg os "$OS_TYPE" \
    --argjson items "$items_json" --argjson warnings "$warns" \
    --argjson protected_skipped "$skips" --argjson manual_steps "$manuals" \
    --argjson needs_approval "$needs_approval" '
    ($items | map(.category) | group_by(.) | map({key:.[0], value:length}) | from_entries) as $counts
    | ($items | map(select(.safety!="report_only") | .size_bytes) | add // 0) as $reclaimable
    | {manifest_file:$manifest_file, mode:$mode, os:$os,
       category_counts:$counts, item_count:($items|length),
       total_reclaimable_bytes:$reclaimable,
       warnings:$warnings, manual_steps:$manual_steps,
       protected_skipped:$protected_skipped,
       needs_approval:(if ($items|length)==0 then false else $needs_approval end)}'
}

cmd_discover() {
  MODE="${1:-}"
  case "$MODE" in audit|quick|deep) ;; *) _die "usage: clean.sh discover <audit|quick|deep>" ;; esac
  _clean_new_item_ctx
  run_sections
  local mf; mf=$(write_manifest)
  emit_skill_json "$mf"
  _clean_free_item_ctx
}

# ── entrypoint ───────────────────────────────────────────────────
case "${1:-}" in
  discover) shift; cmd_discover "$@" ;;
  apply)    _die "apply not yet implemented (T1, next commit)" ;;
  *) _die "usage: clean.sh discover <audit|quick|deep> | apply <manifest>" ;;
esac
