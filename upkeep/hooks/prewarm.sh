#!/usr/bin/env bash
# upkeep — gated SessionStart eager-discovery pre-warm (v1.8, T9).
#
# DEFAULT OFF. Pre-warming runs du/find over the disk; doing that on every
# Claude Code session start would tax users who never clean. So it only fires
# when explicitly enabled, and even then it backgrounds + detaches so session
# start NEVER waits on the scan.
#
# Enable:  touch "${UPKEEP_DATA_DIR:-$HOME/.claude/data}/upkeep-prewarm-enabled"
#          (or export UPKEEP_PREWARM=1)
# Mode:    UPKEEP_PREWARM_MODE (default quick)
set -u

_data="${UPKEEP_DATA_DIR:-$HOME/.claude/data}"
_flag="$_data/upkeep-prewarm-enabled"
if [ "${UPKEEP_PREWARM:-0}" != "1" ] && [ ! -f "$_flag" ]; then
  exit 0   # not enabled — zero cost, return immediately
fi

_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
_engine="$_dir/../skills/upkeep/scripts/clean.sh"
[ -f "$_engine" ] || exit 0

# Detach so the session start never blocks on the disk scan. Reuse is governed
# by the manifest TTL inside clean.sh, so a pre-warm older than the TTL is
# simply ignored by the next discover.
( bash "$_engine" prewarm "${UPKEEP_PREWARM_MODE:-quick}" >/dev/null 2>&1 & ) >/dev/null 2>&1 &
exit 0
