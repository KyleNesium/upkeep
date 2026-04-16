# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.6] - 2026-04-16

### Fixed
- `touch` command was missing from `allowed-tools` in all four cleanup/audit skills — the passive update check calls `touch "$_CHECK_FILE"` to throttle git fetches to once per 24h, but without this permission the file was never written, causing a redundant fetch on every single run.
- Phase 5 (LaunchAgents): `[[ "$label" == homebrew.mxcl.* ]] && continue` short-circuited before the orphaned-homebrew-service check could run — orphaned `homebrew.mxcl.*` agents were never detected. Replaced with an `if/continue` block that checks for orphaned formulas before skipping.
- Phase 12 (Large File Scan): `find` command printed file paths only — "report with sizes" was unworkable. Added `-exec du -sh {} +` with `sort -rh` to output sizes directly.
- Phase 11 (Electron Caches): `find` command included `~/Library/Application Support/Claude/` in its results even though the rules prohibit touching it. Added `-not -path "*/Claude/*" -not -path "*/Claude"` guards to the find command in all three cleanup skills (upkeep, cleandeep, cleanquick) and audit.
- Update skill Step 4: `git symbolic-ref --quiet HEAD` was missing `-C "$d"` — without it the command checked the CWD (the upkeep repo itself) instead of the skill being updated, giving wrong detached-HEAD results. Fixed to `git -C "$d" symbolic-ref --quiet HEAD` and added `Bash(git -C * symbolic-ref *)` to `allowed-tools`.
- Phase 10 (Shell Config): `~/.zshenv` was listed in Edit `allowed-tools` but omitted from the read/audit list. Added to Phase 10 in upkeep, cleandeep, and audit skills.
- Phase 9 (Stale Logs): Phase 9 only did `ls ~/Library/Logs/` — the instruction to flag rotated files (`*.old`, `*.log.N`) and large logs (>10MB) had no backing `find` commands. Added explicit `find` commands for both cases.
- Phase 8 (Build Artifacts): Scan patterns were missing `target/` (Rust/Maven), `Pods/` (CocoaPods), `.build/` (Swift PM), `out/`, `coverage/`, `.nx/`. Added to find command in all four skills.

### Added
- `dev-tool-caches.md`: Added Playwright, Dart/Flutter pub-cache, Swift PM, Terraform plugin-cache, asdf, volta, mise, Deno, Ruby gem specs, node-gyp, Bundler, Bazel.
- `known-cli-dotdirs.md`: Added fnm, asdf, mise, deno, swiftpm, pub-cache, terraform, ansible, helm, kube, aws, gcloud, pulumi, heroku, fly, vercel, netlify, dagger to valid tool dotdirs. Added windsurf, vagrant.d, phpls to common orphan dotdirs.
- Update mode: Added `uv`, `bun`, `deno`, `mise` to the package update table (Step 5) in both update and main upkeep skills.
- Audit skill Rules section expanded: added rules for Apple system dir skipping, Keychains/Preferences protection, conditional-block handling.

### Fixed (additional)
- Phase 9 (Stale Logs): rotated log `find` command had `-o \( -name "*.log.[0-9]*" \)` as a top-level OR expression, not inside the `-maxdepth 3` scope — the depth limit only applied to the first group, so the scan could traverse unboundedly into the second. Merged all patterns into a single grouped expression.
- Phase 2 (Homebrew): `brew leaves` prompt was vague ("ask if any should go") — no structure for user input. Now explicitly prompts: "Uninstall any of these? (space-separated names, or 'none')" to match the selection format used by Phase 5 (LaunchAgents).
- Phase 6 (Xcode): CoreSimulator row offered `xcrun simctl delete unavailable` with no preview of what would be removed. Now counts shutdown simulators first (`xcrun simctl list devices | grep -c Shutdown`) before offering the delete command.

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

[1.0.2]: https://github.com/KyleNesium/upkeep/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/KyleNesium/upkeep/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/KyleNesium/upkeep/releases/tag/v1.0.0
