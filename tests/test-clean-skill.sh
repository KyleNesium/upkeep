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
# clean.sh guards its CLI behind a sourced-check, so sourcing it here just
# exposes its functions (e.g. _clean_dispatch_nonpath) for unit tests.
# shellcheck source=../upkeep/skills/upkeep/scripts/clean.sh
. "$SCRIPTS/clean.sh"

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
mkdir -p "$DHOME/Library/Developer/Xcode/DerivedData/App-abc"
mkdir -p "$DHOME/Library/Application Support/MobileSync/Backup/00008110-DEAD"
mkdir -p "$DHOME/Downloads"; : > "$DHOME/Downloads/installer.dmg"
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

# new macOS sections appear in deep with the right action/safety
XC=$(jq -r '[.items[]|select(.category=="xcode" and .action=="rm" and .safety=="safe")]|length' "$DEEP_MF" 2>/dev/null)
_test "deep: xcode DerivedData (rm/safe)" "$([ "$XC" -ge 1 ] 2>/dev/null && echo true || echo false)" "$XC" ">=1"
IOS=$(jq -r '[.items[]|select(.category=="ios_backup" and .action=="mobilesync_rm")]|length' "$DEEP_MF" 2>/dev/null)
_test "deep: ios_backup (mobilesync_rm/warn)" "$([ "$IOS" -ge 1 ] 2>/dev/null && echo true || echo false)" "$IOS" ">=1"
LF=$(jq -r '[.items[]|select(.category=="large_file")]|length' "$DEEP_MF" 2>/dev/null)
_test "deep: large_file (.dmg) discovered" "$([ "$LF" -ge 1 ] 2>/dev/null && echo true || echo false)" "$LF" ">=1"
# new sections must NOT appear in quick (quick is the lightweight subset)
QXC=$(jq -r '[.items[]|select(.category=="xcode" or .category=="ios_backup")]|length' "$MF" 2>/dev/null)
_test "quick excludes xcode/ios_backup" "$([ "$QXC" = "0" ] && echo true || echo false)" "$QXC" "0"

# empty tree → no approval, zero items
EHOME=$(mktemp -d "${TMPDIR:-/tmp}/upkeep-clean-empty.XXXXXX")
EMPTY_JSON=$(HOME="$EHOME" UPKEEP_DATA_DIR="$EHOME/data" /bin/bash "$CLEAN" discover quick 2>/dev/null)
EC=$(printf '%s' "$EMPTY_JSON" | jq -r '.item_count')
ENA=$(printf '%s' "$EMPTY_JSON" | jq -r '.needs_approval')
_test "empty tree → 0 items, no approval" "$([ "$EC" = "0" ] && [ "$ENA" = "false" ] && echo true || echo false)" "items=$EC approval=$ENA" "0/false"
rm -rf -- "$DHOME" "$EHOME"

echo "── Apply dispatcher ──"
_fresh_apply_home() {
  AHOME=$(mktemp -d "${TMPDIR:-/tmp}/upkeep-clean-apply.XXXXXX")
  mkdir -p "$AHOME/Library/Caches/com.foo" "$AHOME/Library/Caches/com.bar" "$AHOME/.Trash/junk"
  echo x > "$AHOME/Library/Caches/com.foo/f"
  mkdir -p "$AHOME/workspace/p/dist"   # build artifact (report_only in quick)
}
_apply_disc() { HOME="$AHOME" UPKEEP_DATA_DIR="$AHOME/data" /bin/bash "$CLEAN" discover "$1" 2>/dev/null | jq -r .manifest_file; }
_apply_run() { HOME="$AHOME" UPKEEP_DATA_DIR="$AHOME/data" /bin/bash "$CLEAN" apply "$@" 2>/dev/null; }

# 1. removal of safe items
_fresh_apply_home
MF=$(_apply_disc deep)
RES=$(_apply_run "$MF")
GONE=$([ ! -d "$AHOME/Library/Caches/com.foo" ] && echo true || echo false)
_test "apply removes a safe cache dir" "$GONE" "$GONE" "true"
MANGONE=$([ ! -f "$MF" ] && echo true || echo false)
_test "apply consumes the manifest" "$MANGONE" "$MANGONE" "true"
rm -rf -- "$AHOME"

# 2. report_only never deleted (quick build_artifacts)
_fresh_apply_home
MF=$(_apply_disc quick)
_apply_run "$MF" >/dev/null
KEPT=$([ -d "$AHOME/workspace/p/dist" ] && echo true || echo false)
_test "apply never deletes report_only items" "$KEPT" "$KEPT" "true"
rm -rf -- "$AHOME"

# 3. TTL expiry refuses the whole apply
_fresh_apply_home
MF=$(_apply_disc deep)
jq '.created_at = 1' "$MF" > "$MF.t" && mv "$MF.t" "$MF"
ERR=$(_apply_run "$MF" | jq -r '.error // empty')
STILL=$([ -d "$AHOME/Library/Caches/com.foo" ] && echo true || echo false)
_test "stale manifest → apply refused (error)" "$([ -n "$ERR" ] && echo true || echo false)" "$ERR" "non-empty error"
_test "stale manifest → nothing deleted" "$STILL" "$STILL" "true"
rm -rf -- "$AHOME"

# 4. --drop excludes a category
_fresh_apply_home
MF=$(_apply_disc deep)
_apply_run "$MF" --drop=dev_caches >/dev/null
DROPPED=$([ -d "$AHOME/Library/Caches/com.foo" ] && echo true || echo false)
_test "--drop=dev_caches preserves caches" "$DROPPED" "$DROPPED" "true"
rm -rf -- "$AHOME"

# 5. vanished path → skipped (TOCTOU re-stat)
_fresh_apply_home
MF=$(_apply_disc deep)
rm -rf "$AHOME/Library/Caches/com.foo"   # vanish between discover and apply
SK=$(_apply_run "$MF" | jq -r '[.skipped[]|select(.reason=="vanished")]|length')
_test "vanished path skipped at apply" "$([ "$SK" -ge 1 ] 2>/dev/null && echo true || echo false)" "$SK" ">=1"
rm -rf -- "$AHOME"

# 6. type-swap → skipped (dir replaced by a symlink between discover & apply).
# Target a Logs/ dir: it's a safe root these sections don't scan, so it stays
# in place (not in the manifest, never deleted) — keeps the test order-robust.
_fresh_apply_home
mkdir -p "$AHOME/Library/Logs/keep"
MF=$(_apply_disc deep)
rm -rf "$AHOME/Library/Caches/com.foo"
ln -s "$AHOME/Library/Logs/keep" "$AHOME/Library/Caches/com.foo"   # com.foo now a symlink
TS=$(_apply_run "$MF" | jq -r '[.skipped[]|select(.reason=="type-swap")]|length')
_test "type-swap skipped at apply" "$([ "$TS" -ge 1 ] 2>/dev/null && echo true || echo false)" "$TS" ">=1"
rm -rf -- "$AHOME"

# 7. mobilesync_rm removes a single iOS backup dir (per-backup shape)
AHOME=$(mktemp -d "${TMPDIR:-/tmp}/upkeep-clean-apply.XXXXXX")
mkdir -p "$AHOME/Library/Application Support/MobileSync/Backup/00008110-DEAD/info"
MF=$(_apply_disc deep)
_apply_run "$MF" >/dev/null
BGONE=$([ ! -d "$AHOME/Library/Application Support/MobileSync/Backup/00008110-DEAD" ] && echo true || echo false)
BKEEP=$([ -d "$AHOME/Library/Application Support/MobileSync/Backup" ] && echo true || echo false)
_test "mobilesync_rm removes the backup, keeps Backup/" "$([ "$BGONE" = true ] && [ "$BKEEP" = true ] && echo true || echo false)" "gone=$BGONE keepparent=$BKEEP" "true/true"
rm -rf -- "$AHOME"

echo "── Non-path actions (brew/docker, PATH-stubbed) ──"
STUB=$(mktemp -d "${TMPDIR:-/tmp}/upkeep-clean-stub.XXXXXX")
MARKER="$STUB/marker"
cat > "$STUB/brew" <<'SH'
#!/bin/sh
case "$*" in
  "cleanup --dry-run")    echo "Would remove: /old/cache" ;;
  "autoremove --dry-run") echo "abc" ;;
  "cleanup")              echo "brew-cleanup" >> "$CLEAN_TEST_MARKER" ;;
  "autoremove")           echo "brew-autoremove" >> "$CLEAN_TEST_MARKER" ;;
esac
exit 0
SH
cat > "$STUB/docker" <<'SH'
#!/bin/sh
case "$*" in
  "system df")      exit 0 ;;
  "system prune -f") echo "docker-prune" >> "$CLEAN_TEST_MARKER"; exit 0 ;;
esac
exit 0
SH
chmod +x "$STUB/brew" "$STUB/docker"

NPHOME=$(mktemp -d "${TMPDIR:-/tmp}/upkeep-clean-np.XXXXXX")
_np_disc() { HOME="$NPHOME" UPKEEP_DATA_DIR="$NPHOME/data" PATH="$STUB:$PATH" CLEAN_TEST_MARKER="$MARKER" /bin/bash "$CLEAN" discover deep 2>/dev/null; }
NP_MF=$(_np_disc | jq -r '.manifest_file')
BC=$(jq -r '[.items[]|select(.action=="brew_cleanup")]|length' "$NP_MF" 2>/dev/null)
_test "discover: brew_cleanup item (stub)" "$([ "$BC" -ge 1 ] 2>/dev/null && echo true || echo false)" "$BC" ">=1"
DP=$(jq -r '[.items[]|select(.action=="docker_prune")]|length' "$NP_MF" 2>/dev/null)
_test "discover: docker_prune item (stub)" "$([ "$DP" -ge 1 ] 2>/dev/null && echo true || echo false)" "$DP" ">=1"

# apply: brew_cleanup must invoke `brew cleanup` (recorded by the stub)
BC_ID=$(jq -r '.items[]|select(.action=="brew_cleanup")|.id' "$NP_MF" 2>/dev/null | head -1)
: > "$MARKER"
HOME="$NPHOME" UPKEEP_DATA_DIR="$NPHOME/data" PATH="$STUB:$PATH" CLEAN_TEST_MARKER="$MARKER" \
  /bin/bash "$CLEAN" apply "$NP_MF" --items="$BC_ID" >/dev/null 2>&1
INVOKED=$(grep -c 'brew-cleanup' "$MARKER" 2>/dev/null); INVOKED=${INVOKED:-0}
_test "apply: brew_cleanup invokes brew cleanup" "$([ "$INVOKED" -ge 1 ] 2>/dev/null && echo true || echo false)" "$INVOKED" ">=1"

# pipx_uninstall rejects a tool name with shell metachars (identifier validation)
BADREJECT=$(_clean_dispatch_nonpath pipx_uninstall 'evil; rm -rf /' && echo allowed || echo rejected)
_test "non-path: pipx rejects metachar tool name" "$([ "$BADREJECT" = "rejected" ] && echo true || echo false)" "$BADREJECT" "rejected"
rm -rf -- "$STUB" "$NPHOME"

echo "── Linux/WSL2 branch (OS-override + stubbed snap/flatpak) ──"
LSTUB=$(mktemp -d "${TMPDIR:-/tmp}/upkeep-clean-lstub.XXXXXX")
cat > "$LSTUB/snap" <<'SH'
#!/bin/sh
case "$*" in
  "list --all") printf 'core20 x 1822 latest canonical disabled\n' ;;
esac
exit 0
SH
cat > "$LSTUB/flatpak" <<'SH'
#!/bin/sh
case "$*" in
  "list --runtime") echo "org.foo.Runtime" ;;
esac
exit 0
SH
chmod +x "$LSTUB/snap" "$LSTUB/flatpak"
LHOME=$(mktemp -d "${TMPDIR:-/tmp}/upkeep-clean-lhome.XXXXXX")
LJSON=$(HOME="$LHOME" UPKEEP_DATA_DIR="$LHOME/data" PATH="$LSTUB:$PATH" \
        UPKEEP_OS_OVERRIDE=linux UPKEEP_PKG_MGR_OVERRIDE=apt \
        /bin/bash "$CLEAN" discover deep 2>/dev/null)
LMF=$(printf '%s' "$LJSON" | jq -r '.manifest_file')
SUDO=$(printf '%s' "$LJSON" | jq -r '[.manual_steps[]|select(test("sudo apt-get clean"))]|length')
_test "linux: apt cache surfaced as sudo manual step" "$([ "$SUDO" -ge 1 ] 2>/dev/null && echo true || echo false)" "$SUDO" ">=1"
SNAP=$(jq -r '[.items[]|select(.action=="snap_remove")]|length' "$LMF" 2>/dev/null)
_test "linux: snap disabled revision → snap_remove" "$([ "$SNAP" -ge 1 ] 2>/dev/null && echo true || echo false)" "$SNAP" ">=1"
FLAT=$(jq -r '[.items[]|select(.action=="flatpak_unused")]|length' "$LMF" 2>/dev/null)
_test "linux: flatpak unused runtimes → flatpak_unused" "$([ "$FLAT" -ge 1 ] 2>/dev/null && echo true || echo false)" "$FLAT" ">=1"
# snap_remove dispatch rejects a malformed pkg@rev identifier (rev must be digits)
SRBAD=$(_clean_dispatch_nonpath snap_remove 'evil;@x' && echo allowed || echo rejected)
_test "linux: snap_remove rejects bad identifier" "$([ "$SRBAD" = "rejected" ] && echo true || echo false)" "$SRBAD" "rejected"
rm -rf -- "$LSTUB" "$LHOME"

echo "── Wrapper structure (thin two-turn / one-turn) ──"
SKILLS_ROOT="$REPO_ROOT/upkeep/skills"
A="$SKILLS_ROOT/audit/SKILL.md"; Q="$SKILLS_ROOT/cleanquick/SKILL.md"; D="$SKILLS_ROOT/cleandeep/SKILL.md"

_has()  { grep -qF "$2" "$1" && echo true || echo false; }
_lacks(){ grep -qF "$2" "$1" && echo false || echo true; }

# all three call the engine and are tightened (no broad rm / Edit grants)
for f in "$A" "$Q" "$D"; do
  n=$(basename "$(dirname "$f")")
  _test "$n: references clean.sh engine" "$(_has "$f" "clean.sh")" "ref" "clean.sh"
  _test "$n: version bumped to 1.8.0" "$(_has "$f" "version: 1.8.0")" "ver" "1.8.0"
  _test "$n: no broad Bash(rm *) grant" "$(_lacks "$f" "Bash(rm *)")" "grant" "absent"
  _test "$n: no Edit(~/. grant" "$(_lacks "$f" "Edit(~/.")" "grant" "absent"
done

# audit is one-turn report-only — discovers in audit mode, never applies
_test "audit: discovers in audit mode" "$(_has "$A" "discover audit")" "mode" "audit"
_test "audit: never calls clean.sh apply" "$(_lacks "$A" "clean.sh\" apply")" "apply" "absent"

# quick/deep are two-turn — discover + apply
_test "cleanquick: discover quick" "$(_has "$Q" "discover quick")" "mode" "quick"
_test "cleanquick: has apply turn" "$(_has "$Q" "apply \"\$MANIFEST_FILE\"")" "apply" "present"
_test "cleandeep: discover deep" "$(_has "$D" "discover deep")" "mode" "deep"
_test "cleandeep: has apply turn" "$(_has "$D" "apply \"\$MANIFEST_FILE\"")" "apply" "present"

echo ""
echo "════════════════════════════════════════"
printf "PASS: %d   FAIL: %d\n" "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf '\nFailures:\n'; for f in "${FAILURES[@]}"; do printf '  • %s\n' "$f"; done
  exit 1
fi
echo "All clean-validate tests passed."
