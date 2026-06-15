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

# Is canonical path $1 strictly under root $2? Trailing-slash discipline
# prevents `/a/b-evil` from matching root `/a/b`. Equal paths are NOT
# "under" (you can never delete a SAFE_ROOT itself).
_clean_under() {
  [ -n "$1" ] && [ -n "$2" ] || return 1
  [ "$1" = "$2" ] && return 1
  case "$1/" in "$2/"*) return 0 ;; *) return 1 ;; esac
}
