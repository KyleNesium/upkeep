---
name: upkeep:cleandeep
version: 1.8.0
author: KyleNesium
description: |
  Full system deep clean. v1.8 single-shot: a two-turn wrapper over the
  `clean.sh` engine — turn 1 discovers everything and renders one approval gate;
  turn 2 applies the approved set and renders the report. Covers dev caches,
  build artifacts, Electron caches, Xcode DerivedData/Archives, iOS backups,
  large files, orphaned LaunchAgents, Homebrew cleanup/autoremove, Docker prune
  (macOS); ~/.cache, snap disabled revisions, flatpak unused runtimes
  (Linux/WSL2); apt/dnf/pacman cache surfaced as manual sudo steps (never run).
  All deletion goes through a hardened path-safety validator (canonical
  containment + per-action shape + TOCTOU re-check) and per-item failure
  isolation. Asks before removing anything.
  Use when: "clean up my mac", "disk cleanup", "free up space", "deep clean",
  "full cleanup", "new machine setup", "mac cleanup", "clean everything".
allowed-tools:
  # The cleanup engine is the ONLY mutation path (A1 trust boundary): the
  # validator inside clean.sh is the audited boundary, not a broad rm/brew grant.
  - Bash(bash *clean.sh *)
  # Read-only environment queries for the gate header
  - Bash(uname *)
  - Bash(df *)
  - Bash(du *)
  - Bash(sw_vers *)
  - Bash(echo *)
  - Read
  - Glob
  - Grep
---

# /upkeep:cleandeep — Full System Deep Clean

Exactly **two turns**. Turn 1 discovers + renders the gate and ENDS at the
`AskUserQuestion`. Turn 2 applies and renders the report. Never print the gate
and apply in the same response.

The engine lives in the umbrella skill's `scripts/` dir;
`${CLAUDE_SKILL_DIR}` is this SKILL.md's absolute directory.

## Turn 1 — Discover + gate

Disk pre-flight (sub-second), then discover:

```bash
FREE_GB=$(df -k / 2>/dev/null | awk 'NR==2{print int($4/1024/1024)}')
[ -n "$FREE_GB" ] && [ "$FREE_GB" -lt 2 ] && echo "⚠ Only ${FREE_GB}GB free on /."
bash "${CLAUDE_SKILL_DIR}/../upkeep/scripts/clean.sh" discover deep
```

The script prints JSON: `{manifest_file, mode, os, category_counts,
item_count, total_reclaimable_bytes, warnings[], manual_steps[],
protected_skipped[], needs_approval}`.

**Short-circuits:**
- `item_count == 0` AND no `manual_steps[]` → "Nothing to clean." Stop.
- `item_count == 0` but `manual_steps[]` present (Linux: only sudo system-package
  work remains) → render those steps, do NOT say "all clean". Stop.

**Otherwise render the gate** (only non-zero categories):

```
Deep clean plan (<total_reclaimable_bytes> reclaimable):
  dev_caches (N)      ...GB     safe
  build_artifacts (N) ...GB     ⚠ report-only in deep? no — removable
  electron (N)        ...MB     safe (apps not running)
  xcode (N)           ...GB     DerivedData safe / Archives ⚠ may keep
  ios_backup (N)      ...GB     ⚠ local device backups
  large_file (N)      ...MB     ⚠ verify first
  launchagent (N)     —         orphaned (target missing)
  brew / docker       ...GB     reclaimable
  snap / flatpak (N)  ...MB     Linux user-scoped

Warnings:
  • <one line per warnings[] entry>

Manual (you run these — upkeep never uses sudo):
  • <one line per manual_steps[] entry, verbatim>
```

Print this disclaimer directly above the question, always:

```
⚠ Cleanup deletes files. Items marked safe are caches/artifacts that rebuild;
  items marked ⚠ (iOS backups, Xcode Archives, large files) may be data you
  want to keep. Review before approving. Deletion is validated (canonical
  containment + per-action shape) but you are the final check.
```

Then a single `AskUserQuestion`:
- A) Apply all (everything except report_only / opt-in)  *(recommended)*
- B) Drop categories — choose which to exclude
- C) Cancel

On **B**, a second multi-select `AskUserQuestion` with one option per non-zero
category; collect the dropped ids into `$DROP_CSV` (comma-joined).

**End the turn at the `AskUserQuestion`.**

## Turn 2 — Apply

On approval, in a new turn, using the `manifest_file` from Turn 1:

```bash
bash "${CLAUDE_SKILL_DIR}/../upkeep/scripts/clean.sh" apply "$MANIFEST_FILE" \
  ${DROP_CSV:+--drop="$DROP_CSV"}
```

The script: enforces the 15-min manifest TTL; re-validates every item through
the path-safety boundary; TOCTOU re-stat (vanished / type-swap / size-drift →
skip); re-checks `pgrep` for Electron apps; dispatches hardcoded commands
per action with per-item isolation; reports before/after disk delta; consumes
the manifest. Output JSON: `{applied[], failed[], skipped[], applied_count,
failed_count, skipped_count, reclaimed_bytes}`.

If the output has an `error` field (e.g. stale manifest), surface it and tell
the user to re-run — do not retry blindly.

### Report render

```
── Deep Clean Report ───────────────────────────────────
  Removed:   <applied_count> items, ~<reclaimed_bytes> reclaimed
  Skipped:   <skipped_count>  (<reason per skipped[] entry: vanished / type-swap /
             size-drift / app-running / dropped-category / protected>)
  Failed:    <failed_count>   (<reason per failed[] entry>)

── Manual (run yourself) ───────────────────────────────  (if any)
  • <manual_steps[] from the plan — apt/dnf/pacman sudo>
```

## Rules

- Two turns, always. Gate ENDS turn 1; apply is turn 2.
- The engine is the only mutation path — never run `rm`, `brew`, `launchctl`,
  `snap`, etc. directly, and never edit dotfiles. The validator is the boundary.
- Never run sudo — system-package work is surfaced as manual steps.
- report_only items (none in deep today) and opt-in items (pipx) are never
  auto-applied; the user runs those manually.
