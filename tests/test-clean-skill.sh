#!/usr/bin/env bash
# upkeep/clean — regression test suite (v1.8)
#
# Verifies the path-safety validator (THE security boundary) and the
# shared helpers. Runs under stock /bin/bash (macOS 3.2) so the tests
# catch the same portability regressions a real user would hit — NO
# realpath, NO timeout, NO GNU-only flags.
#
# Usage:
#   bash tests/test-clean-skill.sh
#   /bin/bash tests/test-clean-skill.sh    # explicit macOS bash 3.2
#
# Exit: 0 on all-pass, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPTS="$REPO_ROOT/upkeep/skills/upkeep/scripts"

PASS=0
FAIL=0
FAILURES=()

_test() {
  # $1 name, $2 "true"/"false" condition, $3 actual, $4 expected
  if [ "$2" = "true" ]; then
    PASS=$((PASS+1)); printf "  ✅ %s\n" "$1"
  else
    FAIL=$((FAIL+1)); FAILURES+=("$1 (got: $3, want: $4)")
    printf "  ❌ %s (got: %s, want: %s)\n" "$1" "$3" "$4"
  fi
}

# Assert validator verdict. $1 name, $2 raw, $3 action, $4 expected-verb (OK|REFUSE), [$5 expected-reason]
_assert_verdict() {
  local name="$1" raw="$2" action="$3" want_verb="$4" want_reason="${5:-}"
  local out verb reason
  out=$(_clean_validate "$raw" "$action")
  verb=$(printf '%s' "$out" | awk '{print $1}')
  reason=$(printf '%s' "$out" | awk '{print $2}')
  if [ "$verb" != "$want_verb" ]; then
    _test "$name" "false" "$verb" "$want_verb"; return
  fi
  if [ -n "$want_reason" ] && [ "$reason" != "$want_reason" ]; then
    _test "$name [$want_verb]" "false" "$reason" "$want_reason"; return
  fi
  _test "$name" "true" "$out" "$want_verb${want_reason:+ $want_reason}"
}

# ── Build a fake $HOME tree ──────────────────────────────────────
FAKE_HOME=$(mktemp -d "${TMPDIR:-/tmp}/upkeep-clean-test.XXXXXX")
trap 'rm -rf -- "$FAKE_HOME"' EXIT
export HOME="$FAKE_HOME"

mkdir -p "$HOME/Library/Caches/com.example.foo"
mkdir -p "$HOME/Library/Caches/My App With Spaces"
mkdir -p "$HOME/Library/Caches/-rf"
mkdir -p "$HOME/.claude/data"
mkdir -p "$HOME/Library/Application Support/Claude/cache"
mkdir -p "$HOME/Library/Application Support/SomeApp/Cache"
mkdir -p "$HOME/Library/Application Support/MobileSync/Backup/00008110-DEADBEEF"
mkdir -p "$HOME/Library/LaunchAgents"
: > "$HOME/Library/LaunchAgents/com.foo.agent.plist"
: > "$HOME/Library/LaunchAgents/homebrew.mxcl.redis.plist"
mkdir -p "$HOME/Library/LaunchAgents/somedir"
# deep (>256-char) cache path for the C2 fidelity test
LONGSEG=$(printf 'n%.0s' $(seq 1 60))
DEEP="$HOME/Library/Caches/$LONGSEG/$LONGSEG/$LONGSEG/$LONGSEG/$LONGSEG"
mkdir -p "$DEEP"
# symlink escape: a cache entry that points into the protected ~/.claude
ln -s "$HOME/.claude" "$HOME/Library/Caches/evil-link"

# ── Source under test (after HOME is set so root lists resolve to fake) ──
# shellcheck source=../upkeep/skills/upkeep/scripts/lib/common.sh
. "$SCRIPTS/lib/common.sh"
# shellcheck source=../upkeep/skills/upkeep/scripts/clean-validate.sh
. "$SCRIPTS/clean-validate.sh"

echo "── Path validator: legit cases (allowed) ──"
_assert_verdict "legit cache dir"            "$HOME/Library/Caches/com.example.foo" rm OK
_assert_verdict "cache dir with spaces"      "$HOME/Library/Caches/My App With Spaces" rm OK
_assert_verdict "cache dir leading-dash name" "$HOME/Library/Caches/-rf" rm OK
_assert_verdict "C2: >256-char path intact"  "$DEEP" rm OK
_assert_verdict "electron leaf Cache"        "$HOME/Library/Application Support/SomeApp/Cache" electron_cache OK
_assert_verdict "launchagent plist"          "$HOME/Library/LaunchAgents/com.foo.agent.plist" launchctl_rm OK
_assert_verdict "mobilesync single backup"   "$HOME/Library/Application Support/MobileSync/Backup/00008110-DEADBEEF" mobilesync_rm OK

echo "── Path validator: attack battery (refused) ──"
_assert_verdict "traversal into .claude"     "$HOME/Library/Caches/../../.claude" rm REFUSE
# symlink target ~/.claude is outside all safe roots, so containment refuses it
# first (a correct, safe refusal); the protected-override path is proven by the
# App Support/Claude case below. Here we only assert it is REFUSED.
_assert_verdict "symlink escape to .claude"  "$HOME/Library/Caches/evil-link" rm REFUSE
_assert_verdict "outside safe roots (/etc)"  "/etc/passwd" rm REFUSE outside-safe-roots
_assert_verdict "protected under safe root"  "$HOME/Library/Application Support/Claude" rm REFUSE protected
_assert_verdict "protected Claude subdir"    "$HOME/Library/Application Support/Claude/cache" rm REFUSE protected
_assert_verdict "cannot delete safe root itself" "$HOME/Library/Caches" rm REFUSE outside-safe-roots
_assert_verdict "electron non-leaf (app root)" "$HOME/Library/Application Support/SomeApp" electron_cache REFUSE electron-shape
_assert_verdict "launchagent homebrew service" "$HOME/Library/LaunchAgents/homebrew.mxcl.redis.plist" launchctl_rm REFUSE homebrew-service
_assert_verdict "launchagent non-plist dir"  "$HOME/Library/LaunchAgents/somedir" launchctl_rm REFUSE launchagent-shape
_assert_verdict "mobilesync parent (Backup)" "$HOME/Library/Application Support/MobileSync/Backup" mobilesync_rm REFUSE
_assert_verdict "unknown action"             "$HOME/Library/Caches/com.example.foo" frobnicate REFUSE unknown-action

echo "── Shared helpers ──"
LONGTEXT=$(printf 'x%.0s' $(seq 1 400))
SANITIZED=$(_sanitize_text "$LONGTEXT")
_test "sanitize caps free-text at 256" "$([ "${#SANITIZED}" -le 256 ] && echo true || echo false)" "${#SANITIZED}" "<=256"
CTRL=$(_sanitize_text "$(printf 'a\tb\nc')")
_test "sanitize strips control chars" "$([ "$CTRL" = "abc" ] && echo true || echo false)" "$CTRL" "abc"

OS_TYPE=""; UPKEEP_OS_OVERRIDE=linux UPKEEP_PKG_MGR_OVERRIDE=apt _detect_os
_test "OS override seam (linux/apt)" "$([ "$OS_TYPE" = "linux" ] && [ "$PKG_MGR" = "apt" ] && echo true || echo false)" "$OS_TYPE/$PKG_MGR" "linux/apt"
unset UPKEEP_OS_OVERRIDE UPKEEP_PKG_MGR_OVERRIDE

echo "── Discover engine (clean.sh as subprocess) ──"
CLEAN="$SCRIPTS/clean.sh"
DHOME=$(mktemp -d "${TMPDIR:-/tmp}/upkeep-clean-dtest.XXXXXX")
mkdir -p "$DHOME/Library/Caches/com.foo" "$DHOME/.Trash/junk"
mkdir -p "$DHOME/Library/Application Support/Slack/Cache"
mkdir -p "$DHOME/Library/Application Support/Claude/Cache"   # must be excluded
mkdir -p "$DHOME/workspace/proj/node_modules/pkg"
# a first-level cache dir with a 220-char name so its emitted path exceeds
# 256 chars — proves the path field is carried full-fidelity, not truncated (C2)
DLONG=$(printf 'k%.0s' $(seq 1 220))
mkdir -p "$DHOME/Library/Caches/$DLONG"

_discover() { HOME="$DHOME" UPKEEP_DATA_DIR="$DHOME/data" /bin/bash "$CLEAN" discover "$1" 2>/dev/null; }

AUDIT_JSON=$(_discover audit)
NA=$(printf '%s' "$AUDIT_JSON" | jq -r '.needs_approval')
_test "discover audit → needs_approval=false" "$([ "$NA" = "false" ] && echo true || echo false)" "$NA" "false"

QUICK_JSON=$(_discover quick)
NA=$(printf '%s' "$QUICK_JSON" | jq -r '.needs_approval')
_test "discover quick → needs_approval=true" "$([ "$NA" = "true" ] && echo true || echo false)" "$NA" "true"

MF=$(printf '%s' "$QUICK_JSON" | jq -r '.manifest_file')
_test "discover writes a manifest file" "$([ -f "$MF" ] && echo true || echo false)" "$MF" "exists"
CA=$(jq -r '.created_at // empty' "$MF" 2>/dev/null)
_test "manifest carries created_at (for A3 TTL)" "$([ -n "$CA" ] && echo true || echo false)" "$CA" "non-empty"

BA_SAFETY=$(jq -r '[.items[]|select(.category=="build_artifacts")|.safety]|unique|join(",")' "$MF" 2>/dev/null)
_test "quick: build_artifacts safety=report_only" "$([ "$BA_SAFETY" = "report_only" ] && echo true || echo false)" "$BA_SAFETY" "report_only"

DEEP_MF=$(_discover deep | jq -r '.manifest_file')
BA_SAFETY=$(jq -r '[.items[]|select(.category=="build_artifacts")|.safety]|unique|join(",")' "$DEEP_MF" 2>/dev/null)
_test "deep: build_artifacts safety=safe" "$([ "$BA_SAFETY" = "safe" ] && echo true || echo false)" "$BA_SAFETY" "safe"

# Claude App Support cache must NOT appear as an electron item
CLAUDE_HIT=$(jq -r '[.items[]|select(.path|test("Application Support/Claude"))]|length' "$MF" 2>/dev/null)
_test "Claude cache excluded from electron scan" "$([ "$CLAUDE_HIT" = "0" ] && echo true || echo false)" "$CLAUDE_HIT" "0"

# C2: a >256-char path is carried at full fidelity in the manifest
LONGPATH_OK=$(jq -r '[.items[]|select((.path|length)>256)]|length>=1' "$DEEP_MF" 2>/dev/null)
_test "C2: >256-char path preserved in manifest" "$([ "$LONGPATH_OK" = "true" ] && echo true || echo false)" "$LONGPATH_OK" "true"

# empty tree → no approval, zero items
EHOME=$(mktemp -d "${TMPDIR:-/tmp}/upkeep-clean-empty.XXXXXX")
EMPTY_JSON=$(HOME="$EHOME" UPKEEP_DATA_DIR="$EHOME/data" /bin/bash "$CLEAN" discover quick 2>/dev/null)
EC=$(printf '%s' "$EMPTY_JSON" | jq -r '.item_count')
ENA=$(printf '%s' "$EMPTY_JSON" | jq -r '.needs_approval')
_test "empty tree → 0 items, no approval" "$([ "$EC" = "0" ] && [ "$ENA" = "false" ] && echo true || echo false)" "items=$EC approval=$ENA" "0/false"
rm -rf -- "$DHOME" "$EHOME"

echo ""
echo "════════════════════════════════════════"
printf "PASS: %d   FAIL: %d\n" "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf '\nFailures:\n'; for f in "${FAILURES[@]}"; do printf '  • %s\n' "$f"; done
  exit 1
fi
echo "All clean-validate tests passed."
