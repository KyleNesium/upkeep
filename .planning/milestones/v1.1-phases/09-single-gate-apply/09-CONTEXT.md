# Phase 9 Context — Single-Gate Apply + Post-Flight

## Goal

Replace per-category Y/N gates with one approval gate that surfaces the
full Phase 8 plan, runs apply with parallel ecosystems where safe, and
runs a post-flight health check.

## Approval UX

Single AskUserQuestion with the synthesizer's compact summary:

```
Plan:
  Skills (1):     gstack 1.5.1.0 → 1.27.1.0 (major, 31 commits)
  brew  (36):     ⚠ major: node 20→22  | minor: gh, ffmpeg-full, …
  npm   (1):      npm 11.12.1 → 11.14.0
  pipx  (3):      semgrep 1.159.0 → 1.161.0
  gems  (41):     ⚠ major: bundler 1→4, openssl 2→4, nokogiri 1.13→1.19
  uv    (self):   0.9.7 → latest
  bun   (self):   1.3.9 → latest
  mas:            no apps outdated
  macOS:          no updates

Risks flagged:
  • brew:node upgrade may require npm-globals reinstall (deprecation warnings expected)
  • brew:openssl 3.3 → 3.4 affects ruby native gems: nokogiri, openssl
  • gem update will run with --user-install (system Ruby 2.6 detected)
  • PATH shadow: gemini → ~/.local/bin/gemini overrides brew

ETA: ~22 minutes (p50), up to 38 minutes (p90)
Disk free: 124 GB ✓

Apply this plan?
  A) Apply all
  B) Drop categories (interactive multi-select)
  C) Cancel
```

If the user picks B, present a multi-select AskUserQuestion listing each
category as an opt-out.

## Apply orchestration

Per Phase 8 `ordered_groups`:

1. **skills** — serial (1-3 git pulls, fast)
2. **brew** — exclusive (single long command)
3. **language** — parallel where supported, otherwise serial in this phase

   Parallel implementation: emit each command as a `Bash run_in_background`
   call, monitor via TaskGet, aggregate outputs at the end. Limits to 4
   concurrent jobs to avoid CPU thrash.

4. **stores** — serial (mas first, macOS last because of restart)

Each category logs its wall time to `~/.claude/data/upkeep-history.json`.

## Post-flight

Runs after every apply, even on partial failure:

1. `brew doctor 2>&1 | grep -v "^Your system is ready"` — surface only
   if non-empty.
2. For each binary in upgraded brew formulas: `which -a $bin` — report
   any path duplications.
3. Re-resolve any binary that was upgraded: `command -v $bin` — flag
   any that no longer resolve (broken upgrade).
4. Aggregate deprecation warnings from npm/gem/pipx outputs into a
   single section.
5. Final structured report (per Step 6 in v1.0 SKILL.md).

## Failure isolation

Per N4: failures in one ecosystem never block another.

Implementation:
- Each apply command runs with its own try-block (bash `|| true` plus
  exit code capture in the wrapper).
- After each group, classify per-tool result as `✓ / ⚠ / ✗`.
- Aggregate at the end. No early exit unless disk-space pre-flight
  triggered.

## Audit-mode short-circuit

If sub-mode is `audit`, Phase 9 stops after presenting the plan from
Phase 8. No apply, no post-flight, no history write.

## Constraints

- All gates use AskUserQuestion (skill rule).
- No sudo.
- macOS update with `[restart]` always gets explicit confirmation
  (preserved from v1.0).
- macOS update is *not* auto-included in "Apply all" — it's prompted
  separately at the end if present (carry-over from v1.0).

## Risks

- Parallel apply could spike CPU/network. Mitigation: cap at 4 concurrent.
- History file corruption (concurrent writes from a buggy v1.1.x).
  Mitigation: file lock via `flock` — falls back to in-memory if flock
  isn't available.
- Brew upgrade leaves system in inconsistent state if killed. Mitigation:
  document recovery hint (`brew upgrade` is idempotent — re-run).
