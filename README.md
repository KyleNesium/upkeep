<div align="center">

# upkeep

**macOS system cleanup and updater Skill for Claude Code**

Discovery-based disk audit, cleanup, and one-command updates. Finds orphaned app data, stale caches, dead LaunchAgents, and configuration drift. Also updates AI skills (upkeep, gstack, etc.) and package managers (brew, npm, pip, gems, rustup) in one sweep.

[![macOS](https://img.shields.io/badge/macOS-14%2B-000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Claude Code](https://img.shields.io/badge/Claude_Code-skill-7C3AED?logo=data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48cGF0aCBkPSJNMTIgMkw0IDdWMTdMMTIgMjJMMjAgMTdWN0wxMiAyWiIgZmlsbD0id2hpdGUiLz48L3N2Zz4=&logoColor=white)](https://docs.anthropic.com/en/docs/claude-code)
[![Version](https://img.shields.io/github/v/release/KyleNesium/upkeep?color=green)](https://github.com/KyleNesium/upkeep/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

---

<details>
<summary><strong>Table of Contents</strong></summary>

- [Why upkeep?](#why-upkeep)
- [Prerequisites](#prerequisites)
- [Install](#install)
- [Usage](#usage)
- [How It Works](#how-it-works)
- [Cleanup Categories](#cleanup-categories)
- [Modes](#modes)
- [Updating](#updating)
- [Safety](#safety)
- [Privacy](#privacy)
- [Architecture](#architecture)
- [Contributing](#contributing)
- [Changelog](#changelog)
- [Security](#security)
- [Test Coverage](#test-coverage)
- [License](#license)

</details>

---

## Why upkeep?

macOS doesn't clean up after you. Every time you remove an app, install a dev tool, or run a build, it leaves data behind — caches, orphaned support files, stale LaunchAgents, old iOS backups. Over months and years this compounds into dozens of gigabytes that macOS never reclaims automatically.

Most cleanup tools work from a hardcoded list of known apps and paths. **upkeep is discovery-based**: it looks at what's actually installed and cross-references what's left over, so it catches orphaned data from tools that aren't on any list — renamed apps, one-off installers, anything.

First deep clean on a migrated Mac typically recovers **10–50GB**. Monthly quick sweeps keep dev caches and Electron bloat in check with minimal effort.

---

## Prerequisites

- **macOS 14+** (Sonoma or later)
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** (for `/upkeep` slash command)
- **Homebrew** (optional — Phase 2 is skipped if not installed)

---

## Install

```bash
claude plugin add KyleNesium/upkeep
```

Restart Claude Code — the skill is then available as `/upkeep`.

---

## Usage

### Slash commands

```
# Mode selector — asks if no keyword detected
/upkeep                     # asks which mode
/upkeep deep                # full 15-phase audit + cleanup
/upkeep quick               # routine cache + brew sweep
/upkeep audit               # full scan, report only, no changes

# Direct sub-skill commands (bypass mode selector)
/upkeep:cleandeep           # full 15-phase cleanup, no prompt
/upkeep:cleanquick          # fast sweep (phases 1-3, 8, 11, 13), no prompt
/upkeep:audit               # report-only scan, no prompt

# Update mode
/upkeep:update              # asks which update sub-mode
/upkeep:update audit        # check what's outdated, no changes
/upkeep:update skills       # update AI skills only
/upkeep:update packages     # upgrade brew, npm, pip, gems, etc.
/upkeep:update all          # skills + packages, full sweep
```

### Trigger phrases

Claude will load the skill automatically when you ask for a cleanup in natural language. Some examples that work:

- "clean up my mac"
- "free up disk space"
- "audit my mac — what's taking up space?"
- "I just migrated from my old Mac, do a deep clean"
- "quick cleanup"
- "find orphaned app data"
- "update everything"
- "update my AI skills"
- "upgrade my packages"
- "check for updates"

The skill scans your system, presents a summary table with reclaimable space per category, and asks before removing anything. Before/after disk usage comparison at the end.

> [!TIP]
> Run `/upkeep deep` after migrating to a new Mac — migrations carry over gigabytes of orphaned data from apps you no longer use.

---

## How It Works

**Discovery-based, not hardcoded.** Instead of checking a fixed list of known apps and caches, the skill:

1. Lists what's actually installed in `/Applications/`
2. Scans `~/Library/Application Support/`, `~/Library/Containers/`, and `$HOME` dotdirs
3. Cross-references to find **orphaned data** — directories that belong to apps no longer installed
4. Scans `~/.cache/*/` and `~/Library/Caches/*/` for any large cache, not just known ones
5. Auto-discovers project workspace directories (`~/workspace`, `~/dev`, `~/code`, etc.)

This catches cleanup targets that a hardcoded list would miss — new tools, renamed apps, one-off installers.

---

## Cleanup Categories

| # | Category | Deep | Quick | Audit | What it finds | Typical savings |
|---|----------|:----:|:-----:|:-----:|---------------|----------------|
| 1 | Baseline | ✓ | ✓ | ✓ | Disk state snapshot for before/after comparison | — |
| 2 | Homebrew | ✓ | ✓ | ✓ | Outdated packages, stale downloads, orphan deps, deprecated formulae | 500MB – 5GB |
| 3 | Dev caches | ✓ | ✓ | ✓ | npm, bun, yarn, pnpm, uv, pip, puppeteer, Go, cargo, CocoaPods, Gradle, Maven | 1 – 10GB |
| 4 | Orphaned app data | ✓ | | ✓ | Application Support, Containers, dotfiles, Saved State, Crash Reports | 0 – 20GB |
| 5 | LaunchAgents | ✓ | | ✓ | Stale or unloaded agents from removed apps | < 100MB |
| 6 | Xcode & dev tools | ✓ | | ✓ | DerivedData, Archives, iOS DeviceSupport, Simulators | 1 – 20GB |
| 7 | Docker | ✓ | | ✓ | Unused images/containers, orphaned Docker.app data | 0 – 30GB |
| 8 | Build artifacts | ✓ | report | ✓ | node_modules, .venv, .next, dist, \_\_pycache\_\_ across repos | 0 – 10GB |
| 9 | Stale logs | ✓ | | ✓ | `~/Library/Logs/` from removed apps, rotated log files | 100MB – 2GB |
| 10 | Shell config | ✓ | | ✓ | Dead PATH entries, aliases to missing binaries, broken sources | report only |
| 11 | Electron caches | ✓ | ✓ | ✓ | Slack, Spotify, VS Code, Discord cache bloat | 200MB – 3GB |
| 12 | Large files | ✓ | | ✓ | Leftover .dmg, .pkg, .iso, .zip installers | 0 – 10GB |
| 13 | Trash | ✓ | ✓ | ✓ | `~/.Trash/` contents | varies |
| 14 | iOS backups | ✓ | | ✓ | Local iPhone/iPad backups (can be 50-100GB+) | 10 – 100GB |
| 15 | pipx tools | ✓ | | ✓ | Unused CLI tools installed via pipx | 100MB – 2GB |

---

## Modes

### Deep

Full 15-phase audit. Use after migrating to a new Mac, or as a periodic deep clean. Covers everything and offers to clean what it finds. Typical recovery on a migrated Mac: **10-50GB**.

### Quick

Phases 1-3, 8, 11, 13 only. Covers Homebrew, dev tool caches, build artifacts (report only), Electron app caches, and Trash. Skips the slower discovery scans. Good for monthly maintenance. Typical recovery: **1-5GB**.

### Audit

All 15 phases, but **never offers to remove anything**. Pure report — shows what's reclaimable, where space is going, and what might be stale. Use when you want visibility without making changes.

### Update

Separate from cleanup entirely. Discovers what's outdated across AI skills and package managers, then upgrades with per-category confirmation gates. Four sub-modes:

| Sub-mode | What it does |
|----------|--------------|
| `update audit` | Scan everything — show what's outdated, no changes |
| `update skills` | Git-pull all AI skills in `~/.claude/skills/` |
| `update packages` | Upgrade brew, npm globals, pipx, gems, rustup, mas, macOS |
| `update all` | Skills first, then packages — full sweep with per-category gates |

Nothing applies without your approval. `softwareupdate` (macOS system updates) gets an extra restart warning before running.

---

## Updating

Say **"update everything"** in Claude Code, or run `/upkeep:update`.

Four sub-modes:

| Mode | What it does |
|------|--------------|
| `update audit` | Check what's outdated across skills + packages — no changes |
| `update skills` | Git-pull all AI skills (upkeep, gstack, any others in `~/.claude/skills/`) |
| `update packages` | Upgrade brew, npm globals, pipx, gems, rustup, mas, macOS updates |
| `update all` | Skills first, then packages — full sweep |

Everything is confirmation-gated. Nothing applies without your approval. Destructive or disruptive operations (macOS system updates, brew toolchain changes) get extra warnings.

upkeep also checks for updates once per day during any cleanup run and nudges you when one is available.

To disable the daily check: `export UPKEEP_SKIP_UPDATE_CHECK=1`

---

## Safety

| Rule | Detail |
|------|--------|
| Installed apps | Never removes data for apps currently in `/Applications/` |
| Claude data | Never touches `~/.claude/` or `~/Library/Application Support/Claude/` |
| Apple system dirs | Never removes `com.apple.*` directories |
| Keychains & Prefs | Never touches `~/Library/Keychains/` or `~/Library/Preferences/` |
| Size reporting | Always reports sizes before any removal |
| LaunchAgents | Always unloads before deleting plist files |
| Approval required | Always asks before removing brew packages, LaunchAgents, or ambiguous items |
| No sudo | Never runs sudo — surfaces exact commands for you to run manually |
| iOS backups | Explicit warning about backup implications before removal |
| Docker images | Two-tier options: safe prune vs aggressive prune with clear warnings |

---

## Privacy

- **Fully local** — no network calls, no telemetry, no data collection
- All operations run on your machine using standard macOS and Homebrew commands
- The skill only reads filesystem metadata (directory sizes, file lists) and presents findings to you
- Nothing is removed without explicit approval

### Privacy Policy

**Effective date:** April 14, 2026

upkeep is a Claude Code plugin that runs entirely on your local machine. This policy explains what data the plugin accesses and how it is handled.

**Data collection:** None. upkeep makes zero network requests. No telemetry, analytics, crash reports, or usage data are collected or transmitted.

**Data access:** The plugin reads filesystem metadata (directory names, file sizes, modification dates) in standard macOS locations (`~/Library/`, `~/.cache/`, `/Applications/`, `~/Library/LaunchAgents/`, and project workspace directories). This metadata is used solely to identify cleanup candidates and calculate reclaimable disk space. File contents are never read.

**Data storage:** upkeep stores no data. It produces no log files, databases, or caches of its own. All findings are presented in the Claude Code conversation and exist only in that session.

**Data deletion:** When upkeep removes files (with your explicit approval), it uses standard macOS commands (`rm`, `brew cleanup`, `launchctl`). No copies are made. Deleted files go to Trash where applicable, or are permanently removed where noted.

**Third parties:** No data is shared with Anthropic, the plugin author, or any third party. The plugin has no server component.

**Changes:** Updates to this policy will be noted in the repository's commit history. The effective date above reflects the latest revision.

**Contact:** For questions about this policy, open an issue on [GitHub](https://github.com/KyleNesium/upkeep/issues).

---

## Architecture

```
upkeep/
├── .claude-plugin/
│   └── marketplace.json           # Marketplace manifest
├── .github/
│   ├── ISSUE_TEMPLATE/
│   └── PULL_REQUEST_TEMPLATE.md
├── upkeep/
│   ├── .claude-plugin/
│   │   └── plugin.json            # Plugin metadata
│   └── skills/
│       ├── upkeep/
│       │   ├── SKILL.md           # /upkeep — mode selector + all 15 phases
│       │   └── reference/
│       │       ├── dev-tool-caches.md      # Cache paths by tool
│       │       ├── apple-system-dirs.md    # Protected system directories
│       │       └── known-cli-dotdirs.md    # CLI tool dotdir ownership
│       ├── audit/
│       │   └── SKILL.md           # /upkeep:audit — report-only scan (all 15 phases)
│       ├── cleandeep/
│       │   └── SKILL.md           # /upkeep:cleandeep — full 15-phase cleanup
│       ├── cleanquick/
│       │   └── SKILL.md           # /upkeep:cleanquick — fast sweep (phases 1-3, 8, 11, 13)
│       └── update/
│           └── SKILL.md           # /upkeep:update — update skills + package managers
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
├── README.md
└── SECURITY.md
```

Each skill is a `SKILL.md` — a structured prompt that Claude Code follows when invoked. Sub-skills (`audit`, `cleandeep`, `cleanquick`, `update`) are direct-invocation shortcuts; `/upkeep` is the mode-selector entry point that routes to the same logic. Reference files provide lookup tables for cache locations, protected directories, and CLI tool ownership. No runtime dependencies, no binaries, no build step.

---

## Contributing

1. Fork the repo
2. Edit the relevant `SKILL.md` — the main skill at `upkeep/skills/upkeep/SKILL.md`, or a sub-skill (`audit/`, `cleandeep/`, `cleanquick/`, `update/`)
3. Test by running the affected command in Claude Code pointed at your fork
4. Open a PR with a description of what you changed and why

Ideas for contributions:
- New cleanup categories (e.g., Time Machine local snapshots, Rosetta 2 cache)
- Smarter orphan detection heuristics
- Platform support beyond macOS

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release history.

---

## Security

upkeep runs locally and modifies your filesystem. See [SECURITY.md](SECURITY.md) for the full security model, guarantees, and vulnerability reporting process.

---

## Test Coverage

Prompt-based skill — no executable source code. Tested via live invocation against all five entry points on macOS.

| Command | What's validated |
|---------|-----------------|
| `/upkeep` | Mode selection routing, keyword detection |
| `/upkeep:cleandeep` | Full 15-phase execution, phase ordering, safety rules |
| `/upkeep:cleanquick` | Phases 1-3, 8, 11, 13 only; build artifacts report-only enforcement |
| `/upkeep:audit` | All 15 phases, zero mutations, accurate size reporting |
| `/upkeep:update` | Sub-mode detection, skill discovery, package manager audit, per-category gates |

---

## License

[MIT](LICENSE)
