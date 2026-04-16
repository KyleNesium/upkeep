# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
