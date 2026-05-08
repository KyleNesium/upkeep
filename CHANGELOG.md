# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.2] - 2026-05-08

### Fixed

- **macOS `/upkeep:update` now actually pulls trusted skill repos.** Since
  v1.2.0, the macOS apply dispatcher's `skills)` case was a no-op pointing
  to "Step 4 (Apply Skill Updates)" — but Step 4 lives in the Linux/WSL2
  sequential flow, which the macOS routing reminder explicitly skips. The
  synthesizer still listed `skills` in `ordered_groups`, the dispatcher
  still recorded RC=0 → success → name in `UPGRADED_TOOLS_FILE`, and the
  Step 5m report still printed `gstack ✓ updated 1.5.1.0 → 1.27.1.0` — but
  no `git pull` ever ran. macOS users running `/upkeep:update all` since
  2026-05-07 saw "skills upgraded" in the report while their working
  trees were unchanged.

  Fix: a dedicated **Skills apply phase** now runs inside Step 3m's apply
  orchestration, before the dispatcher iteration. It walks the discovery
  JSON's `git_repos[]`, validates each path is under `~/.claude/skills/`
  or `~/.codex/skills/`, skips dirty trees and detached HEADs, and runs
  `git -C "$path" pull --ff-only origin "$BRANCH"` with the branch from
  `git symbolic-ref --short HEAD` (no synthesizer-authored strings — the
  v1.2.0 hardcoded-dispatcher contract is preserved). The dispatcher's
  `skills)` case is now an honest no-op marker.
- **macOS `skills-scout` no longer fetches from untrusted remotes.** The
  HIGH-3 first-encounter trust gate was implemented for the Linux Step 1
  flow but missing from the macOS parallel scout, which would
  `git fetch --tags -q origin` for every git repo found under
  `~/.claude/skills/*/.git` and `~/.codex/skills/*/.git`. The scout now
  reads `~/.claude/data/upkeep-skill-trust.json` first and skips the
  fetch for any URL not on the trust list, marking the repo
  `untrusted: true` instead. Step 3m's new **Skill trust gate** surfaces
  untrusted remotes via `AskUserQuestion` before the main approval gate.
- **Discovery sanitization is more defensive.** Added `dirty_files`,
  `errors`, and `updates` to the strip list, plus a 256-character cap on
  every remaining string value. The cap defends against future scout
  schemas growing free-text fields the denylist forgets to add — bounded
  identifiers (formula names, version strings, paths) fit comfortably,
  while injection payloads stuffed into surviving fields get truncated.
  A code comment documents the path to convert this to a full allowlist
  in v1.3.

### Changed

- **Router Update Mode redirects to `/upkeep:update` instead of duplicating
  it.** `skills/upkeep/SKILL.md` previously contained a ~300-line copy of
  the Linux/WSL2 sequential update flow, which had already drifted: the
  router's trust gate offered 2 options (A/B) while the canonical
  `skills/update/SKILL.md` version offered 3 (A/B/C with "Show recent
  commits"), and the router had no macOS parallel flow at all. The router
  now ends the turn at an `AskUserQuestion` directing the user to
  `/upkeep:update`, which is where the v1.2 hardening lives. This removes
  the divergence risk where a security patch landing in one file silently
  fails to reach the other.
- **Router `allowed-tools` tightened.** Removed `Bash(rustup *)`,
  `Bash(mas *)`, `Bash(softwareupdate *)`, `Bash(deno *)`, `Bash(mise *)`,
  `Bash(git -C * status *)`, `Bash(git -C * pull *)`, and
  `Bash(git -C * remote *)` — these were only used by the now-redirected
  Update Mode body. The remaining git ops cover the self-update check
  only (`rev-parse`, `fetch`, `log`, `show`, `symbolic-ref`).
- **`shadow-scout` does a single PATH walk instead of `which -a` per
  binary.** Apple Silicon brew has hundreds of binaries under
  `${PREFIX}/bin`; the old method forked once per file. The replacement
  walks `$PATH` once with `awk` and emits a duplicate entry whenever the
  brew prefix appears after another directory for a given binary name —
  same semantics, hundreds fewer process launches.

### Notes

- **No CHANGELOG entry for the version frontmatter resync.** SKILL.md
  `version:` fields, `VERSION`, `plugin.json`, and `marketplace.json`
  all move to `1.2.2` together (per the v1.2.1 lockstep rule).
- **Bootstrap caveat (same as v1.2.1).** Pre-1.2.2 users must run
  `/plugin update upkeep@<owner>` (or `/upkeep:update` for git-cloned
  installs) once to pick up these fixes. After that, the daily
  self-update check surfaces future updates automatically.
- **Sort comparison limitation noted, not fixed.** The self-update
  version compare uses `sort -V`, which sorts pre-release suffixes
  incorrectly (`1.2.1-beta` is "newer" than `1.2.1`). upkeep doesn't
  ship pre-releases today; revisit if `1.x.y-rc` tags are ever
  published. Inline comment added at `upkeep/skills/upkeep/SKILL.md`
  near the comparison.

## [1.2.1] - 2026-05-08

### Fixed

- **Self-update check now actually fires for plugin-managed installs.** The
  Phase 1 baseline check ran `git fetch` against the install directory, which for
  plugin-cache installs (`~/.claude/plugins/cache/<owner>/upkeep/<version>/`) is
  not a git working tree. The check failed silently via `2>/dev/null` and the
  "ℹ upkeep update available" nudge never appeared, leaving plugin-managed users
  on stale versions indefinitely (the most common deployment). The new check
  detects install layout: plugin-cache installs read the installed `plugin.json`
  and compare against `origin/main:upkeep/.claude-plugin/plugin.json` in the
  sibling marketplace clone at `~/.claude/plugins/marketplaces/<owner>/`;
  git-cloned skills walk up to the working tree via
  `git rev-parse --show-toplevel` and compare `HEAD..origin/main`. The nudge now
  reports `current → latest` plus the exact update command for the install type
  (`/plugin update upkeep@<owner>` or `/upkeep:update`).
- **Self-update is now an interactive gate, not a passive print.** When the
  check reports an update is available, `/upkeep:upkeep` ends the turn at an
  `AskUserQuestion` ("Update now (recommended)" / "Continue anyway") before
  running Mode Selection or any cleanup phases. This matches the v1.2
  Discover/Approve separation contract and ensures users are running with the
  v1.2.0 security hardening before any mutating action.
- Removed the dead self-check from `/upkeep:audit`, `/upkeep:cleandeep`, and
  `/upkeep:cleanquick`. Those skills had no `git` entry in `allowed-tools` so
  the inline check could never run regardless of install layout. Direct
  invocations of those skills now point users to `/upkeep` for the self-update
  prompt.
- Added `Bash(git -C * show *)` to `/upkeep:upkeep` `allowed-tools` (required
  by the layout-aware check to read upstream `plugin.json` / `VERSION` from
  `origin/main` without mutating the working tree).
- `set -euo pipefail` added to the macOS update synthesizer's `mktemp`+`trap`
  setup and the discovery-input sanitization step. Silent `mktemp` failure
  could leave the trap expanding to `rm -f -- ""` while subsequent appends
  targeted unset paths; silent `jq` failure during sanitization could leave
  `DISCOVERY_JSON` unset, falling back to unsanitized upstream metadata in the
  synthesizer prompt and defeating the v1.2.0 prompt-injection defense
  (CRIT-1+2). Strict mode aborts the apply pipeline so the failure is visible
  instead of silently downgrading.

### Changed

- Bumped `version:` frontmatter in all five `SKILL.md` files from the stale
  `1.1.0-dev` placeholder to `1.2.1`. SKILL frontmatters had drifted from the
  repo's `VERSION` / `plugin.json` / `marketplace.json` since v1.1.0; this
  resyncs them. Future releases should keep these in lockstep.

### Notes

- **Bootstrap cost of the self-update fix.** Users on any pre-1.2.1 version
  will not see the new gate automatically — they must run
  `/plugin update upkeep@<owner>` (or `/upkeep:update` for git-cloned installs)
  once to pick up 1.2.1. After that, future updates surface automatically via
  the now-functional daily check.

## [1.2.0] - 2026-05-07 — Security Hardening

### Fixed (security review findings)

- **CRIT-1+2 — eval injection chain.** Removed `eval "$CMD"` from the macOS
  apply orchestrator. Apply commands are now hardcoded in a case-statement
  dispatcher keyed by tool id (`brew`/`npm`/`pipx`/`gems`/`uv`/`bun`/`mas`/
  `macos`/`skills`); the synthesizer LLM cannot author shell strings. The
  only synthesizer-chosen flag is `gems.user_install`, read as a boolean.
  Discovery JSON is sanitized before being pasted into the synthesizer
  prompt — `newest_commit_subjects`, `breaking_lines`, `description`,
  `release_notes`, `commit_messages`, and `changelog` fields are stripped
  to close the prompt-injection vector via upstream-controlled text. Plan
  tool ids are allowlisted before iteration.
- **HIGH-3 — supply-chain trust.** Replaced the substring-match remote URL
  check (`must contain "KyleNesium/upkeep"`) with an exact case-statement
  match against the four canonical forms; URLs like
  `https://evil.example/?KyleNesium/upkeep` no longer pass. Added a
  first-encounter trust gate for third-party Claude skill repos backed by
  `~/.claude/data/upkeep-skill-trust.json`; unknown remotes surface an
  `AskUserQuestion` before any `git fetch`.
- **HIGH-4 — approval-gate enforcement.** Added a "Hard Rule: Discover and
  Apply must be separate turns" near the top of `upkeep`/`cleandeep`/
  `cleanquick`/`update`. Phases that mutate the filesystem must end
  the turn at the `AskUserQuestion`; the next turn runs only the approved
  items. Prose-only gates (size + `rm` in the same turn) are explicitly
  banned.
- **MED-5 — path-substitution quoting.** Added a "Hard Rule: Path
  substitution must be quoted with `--`" to the rules section of all three
  cleanup skills. Templates carry absolute paths through an index→object
  map and emit `rm -rf -- "$path"` form. LaunchAgent removal template
  rewritten to use `launchctl bootout ... -- "$plist_path"` and
  `rm -f -- "$plist_path"` so plists with spaces or leading dashes target
  the right file.
- **MED-6 — temp-file safety.** Trap in apply orchestration switched to
  single-quoted body so vars expand at fire time, with `rm -f --` to
  resist path edge cases. History writer now uses `mktemp` (no
  predictable `$HIST_FILE.tmp` path susceptible to symlink attack) and
  serializes concurrent `/upkeep:update` runs behind `flock` on Linux/
  WSL2/brew-flock; falls back to atomic mktemp+mv on vanilla macOS.

### Fixed (documentation)

- `CONTRIBUTING.md` referenced 12 paths under the obsolete `plugin/skills/`
  prefix; corrected to current `upkeep/skills/` layout.

## [1.1.0] - 2026-05-07 — Update Skill Overhaul (macOS-only)

### Fixed (gap closure from v1.1 milestone audit)

- **R10 ETA self-tuning** (G1): synthesizer's history input was a literal placeholder; now reads `~/.claude/data/upkeep-history.json` into `$HISTORY_JSON` before invocation. Median-of-5 ETA heuristic is load-bearing on the second run onward.
- **R5 macOS restart gate** (G3): added Hard Rule #8 — synthesizer now propagates `native.softwareupdate.restart_required` into `tool_specs.macos.restart_required`. Step 3m's restart-warning gate has a field to read.
- **R7 PATH shadow vars** (G2): apply orchestration now populates `$UPGRADED_FORMULAS` / `$UPGRADED_TOOLS` via temp-file accumulators (race-safe under POSIX atomic-write guarantees). Step 4m's existing post-flight loops have data to iterate.
- Schema gate added before approval gate: rejects synthesizer plans with the wrong `schema_version` and routes to fallback (G4).
- Compatibility synthesizer Hard Rule #1 extended to consume `severity_on_major` / `severity_on_minor` from `compatibility.json` and sort `plan.warnings[]` by severity (G5).

### Added

- macOS Parallel Flow in `update/SKILL.md`: four parallel scout agents
  (`skills-scout`, `native-scout`, `language-scout`, `shadow-scout`)
  replace the v1.0 sequential discovery on macOS.
- Compatibility synthesizer agent reads scout JSON + a new
  `update/compatibility.json` matrix and emits an ordered apply plan with
  cross-manager risk flags (brew:node ⇒ npm-globals rebuild, brew:openssl
  ⇒ ruby native gems, brew:python ⇒ pipx + uv, etc.).
- Single approval gate replaces per-category Y/N prompts on macOS. Optional
  multi-select drop-categories follow-up keeps user opt-out flexibility.
- Parallel apply for independent ecosystems (npm + pipx + gems + uv + bun
  run concurrently with a 4-job cap; brew runs alone; mas/macOS last).
- Disk-space pre-flight (refuse < 5 GB, warn < 10 GB).
- System Ruby auto-detection (Ruby 2.x at `/usr/bin/ruby`) → `gem update`
  uses `--user-install` automatically, avoiding the silent sudo-required
  failure mode.
- PATH shadow detection: post-flight `which -a` for every upgraded brew
  formula's binaries; surfaces shadowed entries (e.g. brew `gemini` masked
  by another path entry).
- Codex skill auto-update: `~/.codex/skills/*/.git` repos now treated like
  Claude skills — git-pull rather than "manual update required."
- Plugin-managed self-update hint: when upkeep is plugin-managed, the
  report surfaces `/plugin update upkeep` rather than dead-ending.
- ETA in approval gate, with self-tuning history file at
  `~/.claude/data/upkeep-history.json`.
- Post-flight health check: brew doctor (silent unless warnings),
  resolution re-check via `command -v` for each upgraded tool, deprecation
  aggregator across npm/gem/pipx output.
- Final report includes `⚠ Risks observed` and `Manual steps` sections
  before the per-tool ✓/↷/✗ table.
- `compatibility.json` static matrix with seven seed dependency edges.
- Planning artefacts: v1.1 milestone scaffold under `.planning/milestones/`
  and `.planning/phases/07-09-*` with full PLAN/CONTEXT documents.

### Unchanged

- Linux & WSL2 paths: the v1.0 sequential flow (Steps 1–6) remains the
  default for `$OS_TYPE != "macos"`. New parallel flow is gated to macOS;
  Linux/WSL2 port scheduled for v1.1.x.
- Audit / skills / packages / all sub-modes — backwards-compatible with
  every v1.0 invocation form.
- Cleanup skills (`cleanquick`, `cleandeep`, `audit`, umbrella `upkeep`):
  no functional changes in v1.1.

## [1.0.6] - 2026-04-16

### Fixed

- `touch` missing from `allowed-tools` in all four cleanup/audit skills — the 24h update-check throttle silently broke on first run (check file never written → redundant fetch every invocation).
- Phase 5 (LaunchAgents): `[[ "$label" == homebrew.mxcl.* ]] && continue` short-circuited before orphan detection — orphaned Homebrew agents were never flagged. Replaced with `if/continue` block that checks the formula list first.
- Phase 12 (Large File Scan): `find` printed bare paths with no sizes. Added `-exec du -sh {} +` and `sort -rh`.
- Phase 11 (Electron Caches): `find` included `~/Library/Application Support/Claude/`. Added `-not -path "*/Claude/*" -not -path "*/Claude"` guards to all four skills.
- Update skill Step 4: `git symbolic-ref --quiet HEAD` missing `-C "$d"` — checked the upkeep repo instead of the skill being updated. Fixed to `git -C "$d" symbolic-ref --quiet HEAD`; added `Bash(git -C * symbolic-ref *)` to `allowed-tools`.
- Phase 10 (Shell Config): `~/.zshenv` in `allowed-tools` Edit list but missing from the Phase 10 read/audit list in upkeep, cleandeep, and audit.
- Phase 9 (Stale Logs): rotated-file and large-log detection was prose-only — no backing `find` commands. Added `find` with `-exec du -sh {} +` for both cases.
- Phase 9 (Stale Logs): rotated log `find` had a top-level `-o` group outside `-maxdepth 3` scope — depth limit only applied to the first pattern group. Merged all patterns into one grouped expression.
- Phase 9 (Stale Logs): rotated log `find` piped to `xargs du -sh` — on BSD macOS, empty `xargs` input still calls `du -sh` with no args, reporting the current directory. Replaced with `-exec du -sh {} +` throughout (audit, cleandeep, upkeep).
- Phase 8 (Build Artifacts): Scan patterns missing `target/` (Rust/Maven), `Pods/` (CocoaPods), `.build/` (Swift PM), `out/`, `coverage/`, `.nx/`. Added to all four skills.
- Phase 6 (Xcode): CoreSimulator cleanup offered `xcrun simctl delete unavailable` blind — no preview of what would be removed. Now counts shutdown simulators first; command moved out of markdown table cell to avoid pipe-escape ambiguity.
- Phase 2 (Homebrew): `brew leaves` prompt was vague — no defined input format. Now prompts "Uninstall any of these? (space-separated names, or 'none')" to match Phase 5 style.
- `update/SKILL.md` allowed-tools: `bun`, `deno`, `mise`, `uv` used in Steps 2 and 5 but missing — those upgrade commands were silently blocked.
- `upkeep/SKILL.md` allowed-tools: `deno` and `mise` missing from update-mode section.
- `upkeep/SKILL.md` Update Mode Step 2: package discovery block missing `uv`, `bun`, `deno`, `mise` — had drifted from `update/SKILL.md`.
- `upkeep/SKILL.md` heading: stale `# /clean` title from before the v1.0.1 rename; corrected to `# /upkeep`.
- `update/SKILL.md` description: listed old package set (brew, npm, pip, gems, rustup); updated to include bun, deno, mise, uv.
- `README.md` header tagline: same stale package manager list; updated to match.
- `upkeep/SKILL.md` Update Mode Step 1: failure branch said "check for `.git`" — misleading because the `.git` check had already failed. Clarified to "check for `plugin.json`", matching the identical wording in `update/SKILL.md`.
- `marketplace.json` / `plugin.json` descriptions: same stale package list; updated to match.
- Update mode Step 3 overview table: uv, bun, deno, mise absent from the template — model would omit them from the overview even when installed. Added all four tools to both `update/SKILL.md` and `upkeep/SKILL.md`.
- Update mode Step 6 final report template: same omission — uv, bun, deno, mise never appeared in the example output. Added representative rows; note to omit tools not installed.
- `audit/SKILL.md` Phase 6: cleandeep and upkeep got a CoreSimulator reclaimability table in this pass; audit still had the old "report sizes with notes" prose. Added matching table with `xcrun simctl list devices | grep -c Shutdown` count step (report-only; no delete offered).

### Added

- `dev-tool-caches.md`: Playwright, Dart/Flutter, Swift PM, Terraform, asdf, volta, mise, Deno, Ruby gem specs, node-gyp, Bundler, Bazel (12 new entries).
- `known-cli-dotdirs.md`: fnm, asdf, mise, deno, swiftpm, pub-cache, terraform, ansible, helm, kube, aws, gcloud, pulumi, heroku, fly, vercel, netlify, dagger added to valid tool dotdirs; windsurf, vagrant.d, phpls added to common orphan dotdirs (21 new entries).
- Update mode: `uv`, `bun`, `deno`, `mise` added to the Step 5 package update table in both `update/SKILL.md` and `upkeep/SKILL.md`.
- Audit skill Rules: added explicit rules for Apple system dir skipping, Keychains/Preferences protection, and conditional-block handling.

## [1.0.5] - 2026-04-16

### Fixed
- Sub-skills (`audit`, `cleandeep`, `cleanquick`, `update`) appearing in autocomplete without the `upkeep:` namespace prefix — the `name:` field in each skill's `SKILL.md` was set to the bare skill name (e.g. `name: audit`) rather than the namespaced name (`name: upkeep:audit`). Claude Code uses the `name` field directly as the autocomplete entry, so the fix is to include the full `upkeep:` prefix in every sub-skill's `name` field.
- Fixed version mismatch between `marketplace.json` (was `1.0.3`) and `plugin.json` (was `1.0.4`).

## [1.0.4] - 2026-04-16

### Fixed
- Skills still un-namespaced after v1.0.3 fix — root cause was the plugin source directory being named `plugin/` instead of `upkeep/`. Claude Code derives the namespace from the source directory name; `plugin` ≠ `upkeep` so no namespace was applied. Renamed `plugin/` → `upkeep/` and updated `marketplace.json` source path to `"./upkeep"`.

## [1.0.3] - 2026-04-16

### Fixed
- Sub-skills still displaying without namespace (`/audit`, `/update`) instead of `upkeep:audit`, `upkeep:update` — root-level `.claude-plugin/plugin.json` was conflicting with `marketplace.json`, causing the plugin loader to register skills un-namespaced. Removed the duplicate root `plugin.json`; the authoritative manifest is now exclusively `plugin/.claude-plugin/plugin.json`.

## [1.0.2] - 2026-04-16

### Fixed
- Sub-skills displaying without namespace (`/audit`, `/update`) instead of `/upkeep:audit`, `/upkeep:update` — added `"skills"` array to `marketplace.json` plugin entry so Claude Code registers explicit skill paths and applies the `upkeep:` namespace automatically.

### Changed
- README, CONTRIBUTING.md, and issue/PR templates updated to reflect the flat `plugin/skills/` layout introduced in v1.0.1 (architecture diagram was still showing the old nested structure).
- All `/upkeep:clean` command references updated to `/upkeep` (skill was renamed from `clean` → `upkeep` in v1.0.1 but docs weren't updated).

## [1.0.1] - 2026-04-16

### Fixed
- `/upkeep` skill not appearing in slash command autocomplete — skill `name` field was `clean` instead of `upkeep`.
- Sub-skills (`/upkeep:audit`, `/upkeep:cleandeep`, `/upkeep:cleanquick`, `/upkeep:update`) not appearing — they were nested inside `skills/upkeep/` but Claude Code only discovers skills one level deep. Moved all sub-skills to the top of `skills/` and updated `CLAUDE_SKILL_DIR` relative paths accordingly.
- Plugin not loading in sessions outside the project directory — `plugin.json` was missing from the plugin source directory (`plugin/.claude-plugin/plugin.json`) so the installer never copied it into the cache.

## [1.0.0] - 2026-04-16

### Added
- Initial release of **upkeep** Claude Code plugin.
- Five skill entry points: `/upkeep:clean` (mode selector), `/upkeep:cleandeep`, `/upkeep:cleanquick`, `/upkeep:audit`, `/upkeep:update`.
- 15-phase cleanup coverage: Homebrew, dev caches (npm/bun/yarn/pnpm/uv/pip/go/cargo/CocoaPods/Gradle/Maven), orphaned app data, LaunchAgents, Xcode/iOS DeviceSupport/Simulators, Docker, project build artifacts, stale logs, shell config, Electron caches, large installer files, Trash, iOS backups, pipx tools.
- Four operation modes: `deep` (full 15-phase audit + cleanup), `quick` (phases 1-3, 8, 11, 13), `audit` (all phases, report only, never modifies), `update` (update AI skills and package managers).
- **Update mode** — discovers and applies updates to AI skills and package managers in one sweep. Four sub-modes: `audit` (check only), `skills` (git-pull all skills in `~/.claude/skills/`), `packages` (upgrade brew, npm globals, pipx, gems, rustup, mas, macOS), `all` (skills then packages).
- Passive update check on every cleanup run (at most once per 24h, silent on failure).
- Discovery-based orphan detection — scans `/Applications/` and cross-references `~/Library/Application Support/`, `~/Library/Containers/`, and `$HOME` dotdirs.
- Before/after disk usage comparison.
- User confirmation prompts before Saved Application State and Crash Reports cleanup.
- `~/Developer` and `~/Documents` added to project-directory discovery.
- Marketplace manifests (`.claude-plugin/marketplace.json` + `plugin.json`) for plugin distribution.
- Safety rules: never removes data for installed apps, never touches `~/.claude/` or Apple system directories, always reports sizes before removal, always unloads LaunchAgents before deletion, no sudo.
- `CONTRIBUTING.md` with path depth reference table for sub-skill authors.
- `VERSION` file for programmatic version reads during update checks.

[1.0.6]: https://github.com/KyleNesium/upkeep/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/KyleNesium/upkeep/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/KyleNesium/upkeep/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/KyleNesium/upkeep/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/KyleNesium/upkeep/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/KyleNesium/upkeep/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/KyleNesium/upkeep/releases/tag/v1.0.0
