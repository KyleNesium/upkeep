<div align="center">

# upkeep

**Cross-platform system cleanup and updater Skill for Claude Code**

Discovery-based disk audit, cleanup, and one-command updates for macOS 14+, Linux (Debian/Ubuntu, Fedora/RHEL, Arch), and WSL2. Finds orphaned app data, stale caches, dead LaunchAgents, Linux package cruft, systemd journal bloat, and configuration drift. Also updates AI skills (upkeep, gstack, etc.) and package managers (brew, apt/dnf/pacman, snap, flatpak, npm, pipx, gems, rustup, bun, deno, mise, uv) in one sweep.

[![macOS](https://img.shields.io/badge/macOS-14%2B-000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Linux](https://img.shields.io/badge/Linux-Debian%20%7C%20Fedora%20%7C%20Arch-FCC624?logo=linux&logoColor=black)](https://www.kernel.org/)
[![WSL2](https://img.shields.io/badge/WSL2-supported-4EAA25?logo=windowsterminal&logoColor=white)](https://learn.microsoft.com/windows/wsl/)
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

### Supported platforms

- **macOS 14+** (Sonoma or later) — full 15-phase coverage
- **Linux** — Debian/Ubuntu (apt), Fedora/RHEL (dnf), Arch (pacman). Optional: snap, flatpak.
- **WSL2** on Windows 10/11 — Ubuntu, Debian, Fedora, or Arch distro. /mnt/c bridge required for Windows-side bonus phases.

### Required

- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** (for `/upkeep` slash command)

### Optional (detected at runtime — skipped gracefully if absent)

- **macOS:** Homebrew, Xcode Command Line Tools, Docker
- **Linux/WSL2:** apt / dnf / pacman, snap, flatpak, systemd (for journalctl vacuum)
- **Both:** git (for skill updates), node/npm/bun/pipx/uv/cargo/etc. for their respective cache cleanups

---

## Platform Support

upkeep routes each phase based on detected OS. Phases skip cleanly on platforms where they don't apply (e.g., Homebrew on Linux, systemd journal on macOS) with a visible "skipped" note — never errors.

| Platform       | Package managers                                                  | Platform-specific phases                                                                     |
|----------------|-------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| macOS 14+      | brew, mas                                                         | Homebrew, LaunchAgents, Xcode, iOS backups, Electron caches, orphaned app data (mdfind)      |
| Ubuntu/Debian  | apt, snap (opt), flatpak (opt)                                    | apt clean, ~/.cache sweep, journalctl vacuum, snap/flatpak cleanup, orphaned kernels + .deb  |
| Fedora/RHEL    | dnf, flatpak (opt)                                                | dnf clean, ~/.cache sweep, journalctl vacuum, flatpak cleanup, orphaned .rpm + kernels       |
| Arch           | pacman, flatpak (opt)                                             | pacman -Sc, ~/.cache sweep, journalctl vacuum, flatpak cleanup, orphaned packages            |
| WSL2 (Windows) | Linux pkg mgr + Windows audit (winget, scoop, choco — audit only) | Everything Linux offers + Windows %TEMP% and %LOCALAPPDATA% npm/pip cache audit via /mnt/c   |

Detection runs once at the top of every skill invocation via `uname -s`, `/etc/os-release`, and `uname -r | grep -qi microsoft` (for WSL2). The result is exported as `$OS_TYPE`, `$OS_DISTRO`, and `$PKG_MGR` for every downstream phase.

Cross-platform phases that run everywhere: disk baseline (Phase 1), dev tool caches (Phase 3), Docker (Phase 7), project build artifacts (Phase 8), stale logs (Phase 9), shell config audit (Phase 10), large files (Phase 12), trash (Phase 13), pipx tools (Phase 15).

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

| # | Category | Platform | Deep | Quick | Audit | What it finds | Typical savings |
|---|----------|----------|:----:|:-----:|:-----:|---------------|----------------|
| 1 | Baseline | all | ✓ | ✓ | ✓ | Disk state snapshot for before/after comparison | — |
| 2 | Homebrew | macOS | ✓ | ✓ | ✓ | Outdated packages, stale downloads, orphan deps, deprecated formulae | 500MB – 5GB |
| 3 | Dev caches | all | ✓ | ✓ | ✓ | npm, bun, yarn, pnpm, uv, pip, Playwright, Go, cargo, CocoaPods, Gradle, Maven, Dart/Flutter, Swift PM, Terraform, asdf, volta, mise, Deno, Bundler, Bazel, and more | 1 – 10GB |
| 4 | Orphaned app data | macOS | ✓ | | ✓ | Application Support, Containers, dotfiles, Saved State, Crash Reports | 0 – 20GB |
| 5 | LaunchAgents | macOS | ✓ | | ✓ | Stale or unloaded agents from removed apps | < 100MB |
| 6 | Xcode & dev tools | macOS | ✓ | | ✓ | DerivedData, Archives, iOS DeviceSupport, Simulators | 1 – 20GB |
| 7 | Docker | all | ✓ | | ✓ | Unused images/containers, orphaned Docker.app data | 0 – 30GB |
| 8 | Build artifacts | all | ✓ | report | ✓ | node_modules, .venv, .next, dist, \_\_pycache\_\_, target, Pods, .build, out, coverage, .nx across repos | 0 – 10GB |
| 9 | Stale logs | all | ✓ | | ✓ | `~/Library/Logs/` from removed apps, rotated log files | 100MB – 2GB |
| 10 | Shell config | all | ✓ | | ✓ | Dead PATH entries, aliases to missing binaries, broken sources | report only |
| 11 | Electron caches | macOS | ✓ | ✓ | ✓ | Slack, Spotify, VS Code, Discord cache bloat | 200MB – 3GB |
| 12 | Large files | all | ✓ | | ✓ | Leftover .dmg, .pkg, .iso, .zip installers | 0 – 10GB |
| 13 | Trash | all | ✓ | ✓ | ✓ | `~/.Trash/` contents | varies |
| 14 | iOS backups | macOS | ✓ | | ✓ | Local iPhone/iPad backups (can be 50-100GB+) | 10 – 100GB |
| 15 | pipx tools | all | ✓ | | ✓ | Unused CLI tools installed via pipx | 100MB – 2GB |

Platform column: `all` = runs on macOS/Linux/WSL2. `macOS` = skipped with a "skipped (macOS only)" note on Linux/WSL2. Linux adds its own phases (package cache, ~/.cache sweep, journalctl, snap/flatpak, orphaned kernels) documented in the [Platform Support](#platform-support) section. WSL2 adds Windows %TEMP% and %LOCALAPPDATA% bonus phases on top of Linux coverage.

---

## Modes

### Deep

Full 15-phase audit. Use after migrating to a new Mac, or as a periodic deep clean. Covers everything and offers to clean what it finds. Typical recovery on a migrated Mac: **10-50GB**.

### Quick

Phases 1-3, 8, 11, 13 only. Covers Homebrew, dev tool caches, build artifacts (report only), Electron app caches, and Trash. Skips the slower discovery scans. Good for monthly maintenance. Typical recovery: **1-5GB**.

### Audit

All 15 phases, but **never offers to remove anything**. Pure report — shows what's reclaimable, where space is going, and what might be stale. Use when you want visibility without making changes.

### Update

Separate from cleanup entirely. On macOS, four parallel scout agents discover outdated tools, a compatibility synthesizer plans the upgrade order with cross-manager risk flags, and a single approval gate replaces per-category Y/N fatigue. On Linux & WSL2, the v1.0 sequential flow remains unchanged. Four sub-modes:

| Sub-mode | What it does |
|----------|--------------|
| `update audit` | Scan everything — show what's outdated, no changes |
| `update skills` | Git-pull AI skills in `~/.claude/skills/` and `~/.codex/skills/` |
| `update packages` | Upgrade brew, npm globals, pipx, gems, rustup, bun, deno, mise, uv, mas, macOS |
| `update all` | Skills first, then packages — full sweep, single approval gate on macOS |

The macOS flow flags cross-manager risks before you approve (e.g. `brew:node` upgrade ⇒ npm globals may need rebuild; `brew:openssl` upgrade ⇒ ruby native gems like `nokogiri` need recompile; system Ruby 2.x ⇒ `gem update` auto-uses `--user-install`). Post-flight runs `brew doctor`, re-resolves PATH for upgraded binaries, and surfaces shadowed entries.

Nothing applies without your approval. `softwareupdate` (macOS system updates) always gets an extra restart warning, even under "Apply all".

---

## Updating

Say **"update everything"** in Claude Code, or run `/upkeep:update`.

Four sub-modes:

| Mode | What it does |
|------|--------------|
| `update audit` | Check what's outdated across skills + packages — no changes |
| `update skills` | Git-pull all AI skills (upkeep, gstack, any others in `~/.claude/skills/`) |
| `update packages` | Upgrade brew, npm globals, pipx, gems, rustup, bun, deno, mise, uv, mas, macOS updates |
| `update all` | Skills first, then packages — full sweep |

Everything is confirmation-gated. Nothing applies without your approval. Destructive or disruptive operations (macOS system updates, brew toolchain changes) get extra warnings.

On macOS, v1.1 introduces a parallel discovery + compatibility-aware single-gate flow (see Update section above). Linux & WSL2 continue to use the v1.0 sequential per-category gates pending v1.1.x port.

### v1.3: AI update advisor (macOS)

Discovery and apply remained hardcoded for security (see v1.2 hardening), but v1.3 wraps three reasoning agents around them so the approval gate and final report tell you *what each upgrade means*, not just *what's outdated*:

- **`changelog-reader`** — for every major bump and every cross-manager-flagged upgrade, fetches official release notes from an allowlisted set of upstream hosts (`github.com`, `nodejs.org`, `python.org`, `rubygems.org`, etc.) and returns a severity grade (`low|medium|high|critical`), a one-sentence summary, the concrete breaking changes, and any CVEs explicitly fixed. The grep-CHANGELOG approach from v1.2 is replaced.
- **`project-impact`** — walks your workspace roots (`~/workspace`, `~/Github`, `~/Projects`, `~/src`, `~/code`, `~/dev` — whichever exist) and reads per-language manifests (`package.json`, `Gemfile`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `.tool-versions`, `Dockerfile`) to surface "node 26 will affect N of your projects" callouts. Reads only — never executes manifest scripts.
- **`failure-diagnoser`** — fires only when something actually failed during apply. Reads the relevant log excerpt and identifies the root cause from known patterns (missing build deps, version constraints, permission errors, broken native modules after brew major bump), then proposes 1–3 ranked fix options. **All suggested commands are surfaced as text only and are never auto-executed** — you copy them into your shell yourself.

The advisor is layered on top of the v1.2 hardcoded-dispatcher contract: none of these agents author shell commands the orchestrator will execute, all their outputs pass through allowlist-projection sanitization, and the diagnoser's `command` field has an additional denylist scrub for destructive patterns (`rm -rf`, `--force`, `chmod 777`, `curl | sh`, etc.).

When you run `/upkeep` it checks once per day whether a newer version is available. Both install layouts are supported: git-cloned skills compare `HEAD` against `origin/main`, and plugin-managed installs compare the installed `plugin.json` against the marketplace clone. If the check finds an update, you'll be asked whether to update first or continue with the current version. The narrow entrypoints (`/upkeep:audit`, `/upkeep:cleandeep`, `/upkeep:cleanquick`) skip the check — re-enter via `/upkeep` if you want the prompt.

To disable the daily check entirely: `export UPKEEP_SKIP_UPDATE_CHECK=1`

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
- All operations run on your machine using standard system commands (rm, brew, apt/dnf/pacman, launchctl, systemctl, etc.)
- The skill only reads filesystem metadata (directory sizes, file lists) and presents findings to you
- Nothing is removed without explicit approval

### Privacy Policy

**Effective date:** April 14, 2026

upkeep is a Claude Code plugin that runs entirely on your local machine. This policy explains what data the plugin accesses and how it is handled.

**Data collection:** None. upkeep makes zero network requests. No telemetry, analytics, crash reports, or usage data are collected or transmitted.

**Data access:** The plugin reads filesystem metadata (directory names, file sizes, modification dates) in standard system locations (`~/Library/` and `/Applications/` on macOS; `~/.cache/` and package manager metadata on Linux/WSL2; and project workspace directories on all platforms). This metadata is used solely to identify cleanup candidates and calculate reclaimable disk space. File contents are never read.

**Data storage:** upkeep stores no data. It produces no log files, databases, or caches of its own. All findings are presented in the Claude Code conversation and exist only in that session.

**Data deletion:** When upkeep removes files (with your explicit approval), it uses standard system commands (`rm`, `brew cleanup` on macOS, `apt/dnf/pacman autoremove` on Linux, `launchctl` for macOS agents). No copies are made. Deleted files go to Trash where applicable, or are permanently removed where noted.

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

Prompt-based skill — no executable source code. Tested via live invocation against all five entry points across macOS, Linux, and WSL2.

| Command | What's validated |
|---------|-----------------|
| `/upkeep` | Mode selection routing, keyword detection |
| `/upkeep:cleandeep` | Full 15-phase execution, phase ordering, safety rules |
| `/upkeep:cleanquick` | Phases 1-3, 8, 11, 13 only; build artifacts report-only enforcement |
| `/upkeep:audit` | All 15 phases, zero mutations, accurate size reporting |
| `/upkeep:update` (Linux / WSL2) | Sub-mode detection, sequential skill + package discovery, per-category gates |
| `/upkeep:update` (macOS, v1.1) | Parallel scouts, compatibility synthesizer, single approval gate, parallel apply, post-flight (brew doctor, PATH shadow, deprecation aggregator), history-tuned ETA |
| `/upkeep:update` (security, v1.2) | Hardcoded apply dispatcher (no `eval`), allowlisted tool ids, denylist + length-cap discovery sanitization, exact-match remote URL validation, first-encounter trust gate for third-party skill repos, Discover/Approve/Apply turn separation, atomic + `flock`-serialized history writer |
| `/upkeep:update` (regression-fix, v1.2.2) | macOS skills apply phase actually pulls trusted git skill repos (was a silent no-op since v1.2.0); skills-scout no longer fetches from untrusted remotes; router Update Mode redirects to `/upkeep:update` instead of duplicating its logic |

---

## License

[MIT](LICENSE)
