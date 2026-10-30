#!/usr/bin/env bash
# upkeep/common — shared bash helpers (v1.8)
#
# Sourced by clean.sh (and, after the v1.8 final phase, by update's
# discover.sh). Targets stock macOS /bin/bash 3.2 + BSD userland:
# NO realpath, NO timeout, NO GNU-only flags. Canonicalization is
# `cd -P && pwd -P` (the update.sh:401 pattern); see clean-validate.sh.
#
# This file is pure functions + no side effects on source, so it is safe
# to source from a test harness.

# ── OS detection ─────────────────────────────────────────────────
# Sets OS_TYPE (macos|linux|wsl2|unknown), OS_DISTRO, PKG_MGR.
# Test seam: UPKEEP_OS_OVERRIDE / UPKEEP_PKG_MGR_OVERRIDE short-circuit
# the live `uname` so Linux paths can be exercised on a macOS box.
# Ported verbatim from update/discover.sh:81 so both engines agree.
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

# ── Free-text sanitization ───────────────────────────────────────
# 256-char cap + control-char strip + free-text denylist, for fields
# SURFACED to the LLM (labels, app_name, warn_reason). It is a hard
# rule (C2) that this is NEVER applied to a manifest `path` field —
# paths are carried at full fidelity and guarded by the validator, not
# by length. Truncating a deep path (nested node_modules > 256 chars)
# would corrupt the deletion target.
_sanitize_text() {
  # $1: raw text. Echoes the sanitized form.
  local s="$1"
  # strip control chars (incl. newline, CR, tab, ESC) — they have no
  # place in a display label and break table rendering / can spoof output
  s=$(printf '%s' "$s" | tr -d '[:cntrl:]')
  # cap length
  if [ "${#s}" -gt 256 ]; then s="${s:0:253}..."; fi
  printf '%s' "$s"
}

# ── Canonicalization (no realpath) ───────────────────────────────
# Resolve a path to a canonical, symlink-followed absolute path using
# only `cd -P && pwd -P`. Handles three cases:
#   • existing dir   → cd -P; pwd -P
#   • existing file  → canon parent, append basename
#   • vanished leaf  → canon nearest existing parent, append basename
#                      (parent must exist; if the parent is gone too,
#                       returns empty → caller treats as vanished)
# Echoes the canonical path, or empty string on failure.
_clean_canon() {
  local p="$1" parent base canon
  if [ -d "$p" ]; then
    (cd -P -- "$p" 2>/dev/null && pwd -P)
    return
  fi
  parent=$(dirname -- "$p")
  base=$(basename -- "$p")
  canon=$(cd -P -- "$parent" 2>/dev/null && pwd -P)
  [ -z "$canon" ] && return 0   # empty echo → vanished/unresolvable
  printf '%s/%s' "$canon" "$base"
}

# Lexically normalize an absolute path WITHOUT touching the filesystem:
# collapse `//`, drop `.`, resolve `..` against the components seen so far,
# strip any trailing slash. Never follows symlinks — that is the point: the
# validator compares this against _clean_canon to detect a symlinked ancestor.
# Echoes empty for a relative path (callers treat that as unresolvable).
_clean_lexnorm() {
  local p="$1" out="" comp rest
  case "$p" in /*) ;; *) return 0 ;; esac
  rest="${p#/}"
  while [ -n "$rest" ]; do
    case "$rest" in
      */*) comp="${rest%%/*}"; rest="${rest#*/}" ;;
      *)   comp="$rest"; rest="" ;;
    esac
    case "$comp" in
      ''|.) ;;
      ..)   out="${out%/*}" ;;
      *)    out="$out/$comp" ;;
    esac
  done
  printf '%s' "${out:-/}"
}

# Echo $1 if it is a non-negative integer, else the default $2. Every numeric
# UPKEEP_* override goes through this: a typo like UPKEEP_CLEAN_TTL=abc must
# fall back to the safe default, never reach `[ -gt ]` (which then evaluates
# false and fails the guard OPEN) or $(( )) (which aborts mid-apply).
# Capped at 18 digits: 19+ can wrap in 64-bit arithmetic (a huge TTL could
# come back negative or as another huge number). 18 still fits epoch seconds.
_numeric_or() {
  case "${1:-}" in
    ''|*[!0-9]*|???????????????????*) printf '%s' "$2" ;;
    *) printf '%s' "$((10#$1))" ;;
  esac
}

# Version of a skill/plugin repo checkout: VERSION file first, then
# .claude-plugin/plugin.json's "version". NOT a `tr … || jq …` chain: a VERSION
# file that exists but is blank makes `tr` succeed with empty output, so the
# `||` never falls through and a valid plugin.json is shadowed. Echoes empty
# when neither source has a version.
_read_repo_version() {
  local dir="$1" v=""
  [ -f "$dir/VERSION" ] && v=$(tr -d '[:space:]' < "$dir/VERSION" 2>/dev/null)
  [ -z "$v" ] && v=$(jq -r '.version // empty' "$dir/.claude-plugin/plugin.json" 2>/dev/null)
  printf '%s' "$v"
}

# Disk space on / the way the OS reports it, as "<free_gb> <total_gb>" in
# base-10 GB (echoes "0 0" if every source fails). The ONE implementation —
# discover.sh and both SKILL.md pre-flights (via `clean.sh disk`) call this.
#   macOS: URLResourceValues importantUsage/total capacity via osascript — what
#          Finder and System Settings show. "free" includes purgeable space,
#          which Apple documents as available for important writes; df and
#          diskutil omit it and under-report by ~100+ GB. A naive `df /` also
#          sees only the sealed system snapshot, not the APFS container.
#   then diskutil (strictly-free container space), then
#   Linux/WSL2: `df -P -k /` — `-P` is required: GNU df wraps long device
#          names (LVM/mapper, many WSL2 mounts) onto a second line, which
#          shifts the columns and made free read as 0 → update refused to run.
#          Total is df's own size column, not used+avail (ext4 reserves ~5%).
# UPKEEP_DISK_SOURCE=df forces the df path (test seam for the Linux branch).
_disk_gb() {
  local free_b="" total_b="" info
  if [ "${UPKEEP_DISK_SOURCE:-}" != "df" ] && command -v osascript >/dev/null 2>&1; then
    read -r free_b total_b < <(osascript -l JavaScript -e \
'ObjC.import("Foundation");function c(k){var u=$.NSURL.fileURLWithPath("/"),v=Ref(),e=Ref();return u.getResourceValueForKeyError(v,k,e)?v[0].longLongValue:-1;}c($.NSURLVolumeAvailableCapacityForImportantUsageKey)+" "+c($.NSURLVolumeTotalCapacityKey)' 2>/dev/null)
    if ! { [ "${free_b:-0}" -gt 0 ] 2>/dev/null && [ "${total_b:-0}" -gt 0 ] 2>/dev/null; }; then
      free_b=""; total_b=""
    fi
  fi
  if [ -z "$free_b" ] && [ "${UPKEEP_DISK_SOURCE:-}" != "df" ] && command -v diskutil >/dev/null 2>&1; then
    info=$(diskutil info / 2>/dev/null)
    free_b=$(printf '%s\n' "$info" | awk -F'[()]' '/Container Free Space:/{print $2}' | awk '{print $1}')
    total_b=$(printf '%s\n' "$info" | awk -F'[()]' '/Container Total Space:/{print $2}' | awk '{print $1}')
    # Validate EACH value: a joined check would pass "200" + "" (missing
    # total line) and report a 0 GB total.
    case "$free_b" in ''|*[!0-9]*) free_b="" ;; esac
    case "$total_b" in ''|*[!0-9]*) free_b="" ;; esac
  fi
  if [ -n "$free_b" ]; then
    awk -v f="$free_b" -v t="$total_b" 'BEGIN{printf "%d %d\n", (f/1e9)+0.5, (t/1e9)+0.5}'
    return 0
  fi
  # Columns counted from the RIGHT (mount "/" is $NF, capacity $(NF-1),
  # available $(NF-2), size $(NF-4)) so a device name containing spaces can't
  # shift them — counting from the left read the size column as free space.
  df -P -k / 2>/dev/null | awk 'NR==2 && NF >= 6 && $(NF-2) ~ /^[0-9]+$/ && $(NF-4) ~ /^[0-9]+$/ {
    printf "%d %d\n", ($(NF-2)*1024/1e9)+0.5, ($(NF-4)*1024/1e9)+0.5; ok=1 }
    END { if (!ok) print "0 0" }'
}

# Is canonical path $1 strictly under root $2? Trailing-slash discipline
# prevents `/a/b-evil` from matching root `/a/b`. Equal paths are NOT
# "under" (you can never delete a SAFE_ROOT itself).
_clean_under() {
  [ -n "$1" ] && [ -n "$2" ] || return 1
  [ "$1" = "$2" ] && return 1
  case "$1/" in "$2/"*) return 0 ;; *) return 1 ;; esac
}
