#!/usr/bin/env bash
# upkeep/clean — path-safety validator (v1.8)  ── THE SECURITY BOUNDARY
#
# Once cleanup logic runs as a single `bash clean.sh ...` call, the wrapper's
# granular allowed-tools no longer constrains behavior (A1). For a skill that
# DELETES user data, this validator is the audited boundary. It is isolated in
# its own sourceable file so the test battery can hammer it directly.
#
#   ┌─ _clean_validate <raw_path> <action> ────────────────────────────────┐
#   │  1. canonicalize via cd -P/pwd -P (no realpath — macOS bash 3.2)      │
#   │  2. assert canonical ∈ SAFE_ROOTS  (strictly under, never == a root)  │
#   │  3. assert canonical ∉ PROTECTED   (checked AFTER roots; overrides)   │
#   │  4. assert per-ACTION path SHAPE   (containment alone can wipe a tree)│
#   │  echoes "OK <canon>"  → exit 0                                        │
#   │  echoes "REFUSE <reason> <raw>" → exit 1                              │
#   └──────────────────────────────────────────────────────────────────────┘
#
# Depends on lib/common.sh (_clean_canon, _clean_under).

# Resolve lib relative to this file; allow the test harness to pre-source.
if ! command -v _clean_canon >/dev/null 2>&1; then
  _CV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
  # shellcheck source=lib/common.sh
  . "$_CV_DIR/lib/common.sh"
fi

# Canonical $HOME. The root lists must be built from the SAME canonical
# form the validator resolves targets to, or the /tmp→/private symlink (and
# any symlinked $HOME) makes every containment check miss. Resolved once,
# cached, and used by both root-list builders below.
_clean_home() {
  if [ -z "${_CLEAN_HOME:-}" ]; then
    _CLEAN_HOME=$(cd -P -- "$HOME" 2>/dev/null && pwd -P)
    _CLEAN_HOME=${_CLEAN_HOME:-$HOME}
  fi
  printf '%s' "$_CLEAN_HOME"
}

# SAFE_ROOTS — canonical path must be strictly under one of these.
# Built from canonical $HOME so the test harness can point $HOME at a fake tree.
_clean_safe_roots() {
  local H; H=$(_clean_home)
  cat <<EOF
$H/Library/Caches
$H/.cache
$H/.Trash
$H/Library/Logs
$H/Library/Developer/Xcode/DerivedData
$H/Library/Developer/Xcode/Archives
$H/Library/Developer/Xcode/iOS DeviceSupport
$H/Library/Developer/CoreSimulator
$H/Library/Saved Application State
$H/Library/Application Support/MobileSync/Backup
$H/Library/Application Support
$H/Library/LaunchAgents
$H/Downloads
$H/Desktop
$H/workspace
$H/dev
$H/Developer
$H/code
$H/src
$H/projects
$H/repos
EOF
}

# PROTECTED — canonical path must NOT be == or under any of these.
# Checked AFTER SAFE_ROOTS, so it overrides (e.g. Application Support is a
# safe root, but Application Support/Claude is protected).
_clean_protected() {
  local H; H=$(_clean_home)
  cat <<EOF
$H/.claude
$H/.config/claude
$H/Library/Application Support/Claude
$H/Library/Keychains
$H/Library/Preferences
$H/Documents
/System
/Library
/Applications
EOF
}

# Electron cache leaf basenames that are safe to clear (shape gate).
_clean_is_electron_leaf() {
  case "$1" in
    "Cache"|"Code Cache"|"Service Worker"|"CachedData"|"PersistentCache"|"GPUCache") return 0 ;;
    CachedExtension*) return 0 ;;
    *) return 1 ;;
  esac
}

# _clean_validate <raw_path> <action>
# action ∈ rm | electron_cache | launchctl_rm | mobilesync_rm
_clean_validate() {
  local raw="$1" action="$2" canon base parent gparent root ok=0
  local H; H=$(_clean_home)   # canonical home, for the shape-check patterns below

  canon=$(_clean_canon "$raw")
  if [ -z "$canon" ]; then
    printf 'REFUSE unresolvable %s\n' "$raw"; return 1
  fi

  # (2) containment — strictly under a SAFE_ROOT
  while IFS= read -r root; do
    [ -z "$root" ] && continue
    if _clean_under "$canon" "$root"; then ok=1; break; fi
  done <<EOF
$(_clean_safe_roots)
EOF
  if [ "$ok" != "1" ]; then
    printf 'REFUSE outside-safe-roots %s\n' "$raw"; return 1
  fi

  # (3) denylist — not == or under a PROTECTED dir
  while IFS= read -r root; do
    [ -z "$root" ] && continue
    if [ "$canon" = "$root" ] || _clean_under "$canon" "$root"; then
      printf 'REFUSE protected %s\n' "$raw"; return 1
    fi
  done <<EOF
$(_clean_protected)
EOF

  base=$(basename -- "$canon")
  parent=$(dirname -- "$canon")
  gparent=$(dirname -- "$parent")

  # (4) per-action SHAPE
  case "$action" in
    electron_cache)
      # leaf basename must be a known cache dir, under Application Support,
      # never the app container root itself.
      if ! _clean_is_electron_leaf "$base"; then
        printf 'REFUSE electron-shape %s\n' "$raw"; return 1
      fi
      case "$canon/" in "$H/Library/Application Support/"*) ;; *)
        printf 'REFUSE electron-shape %s\n' "$raw"; return 1 ;;
      esac
      ;;
    launchctl_rm)
      # exactly a *.plist directly in ~/Library/LaunchAgents, never a dir,
      # never a brew-managed service.
      case "$parent" in "$H/Library/LaunchAgents") ;; *)
        printf 'REFUSE launchagent-shape %s\n' "$raw"; return 1 ;;
      esac
      case "$base" in
        *.plist) ;; *) printf 'REFUSE launchagent-shape %s\n' "$raw"; return 1 ;;
      esac
      case "$base" in
        homebrew.mxcl.*) printf 'REFUSE homebrew-service %s\n' "$raw"; return 1 ;;
      esac
      ;;
    mobilesync_rm)
      # a single backup dir directly under .../MobileSync/Backup, never the
      # Backup parent itself (the parent-equal case is already caught by the
      # strictly-under SAFE_ROOT check, but assert the shape explicitly).
      case "$parent" in *"/MobileSync/Backup") ;; *)
        printf 'REFUSE mobilesync-shape %s\n' "$raw"; return 1 ;;
      esac
      ;;
    rm)
      : # generic: containment + denylist already enforced
      ;;
    *)
      printf 'REFUSE unknown-action %s\n' "$raw"; return 1
      ;;
  esac

  printf 'OK %s\n' "$canon"; return 0
}
