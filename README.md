<div align="center">

# upkeep

**Disk cleanup and one-gate updates for macOS, Linux, and WSL2 — a Claude Code plugin**

upkeep scans your machine for reclaimable space (caches, Trash, build artifacts, Xcode data, old installers, orphaned LaunchAgents, Docker/Homebrew cruft) and updates your AI skills, Claude Code plugins, and package managers (brew, mas, macOS updates, npm, pipx, gems, uv, bun, deno, mise, rustup, cargo, snap, flatpak) in one sweep. Every change goes through a single approval gate, and every deletion goes through a tested path-safety validator.

[![macOS](https://img.shields.io/badge/macOS-14%2B-000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Linux](https://img.shields.io/badge/Linux-Debian%20%7C%20Fedora%20%7C%20Arch-FCC624?logo=linux&logoColor=black)](https://www.kernel.org/)
[![WSL2](https://img.shields.io/badge/WSL2-supported-4EAA25?logo=windowsterminal&logoColor=white)](https://learn.microsoft.com/windows/wsl/)
[![Claude Code](https://img.shields.io/badge/Claude_Code-plugin-7C3AED?logo=data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48cGF0aCBkPSJNMTIgMkw0IDdWMTdMMTIgMjJMMjAgMTdWN0wxMiAyWiIgZmlsbD0id2hpdGUiLz48L3N2Zz4=&logoColor=white)](https://docs.anthropic.com/en/docs/claude-code)
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
- [Version History](#version-history)
- [Security](#security)
- [Test Coverage](#test-coverage)
- [License](#license)

</details>

---

## Why upkeep?

Machines don't clean up after you. Caches grow without bound, uninstalled apps leave their support data behind, builds leave `node_modules` and `target/` dirs in every repo, and installers pile up in Downloads. Keeping tools current means remembering a dozen different upgrade commands.

upkeep does both jobs from Claude Code, with two design rules:

- **Scripts decide, the model presents.** Discovery, planning, and every destructive action run in tested bash scripts (`clean.sh`, `update.sh`). Claude renders the findings and the approval gate; it never composes the delete or upgrade commands.
- **Nothing changes without one explicit approval**, and deletions are re-validated at apply time (containment, symlink refusal, drift and running-app checks).

---

## Prerequisites

### Supported platforms

- **macOS 14+** (Sonoma or later) — full coverage
- **Linux** — Debian/Ubuntu (apt), Fedora/RHEL (dnf), Arch (pacman). Optional: snap, flatpak.
- **WSL2** on Windows 10/11 — runs the Linux code path; Windows package managers are audit-only in update mode.

### Required

- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)**
- **bash** (stock macOS `/bin/bash` 3.2 is fine) and **`jq`** — the scripts depend on both

### Optional (detected at runtime — skipped if absent)

- **macOS:** Homebrew, mas, Xcode, Docker, pipx
- **Linux/WSL2:** snap, flatpak, Docker, pipx
- **All:** git (skill/marketplace updates); npm, uv, bun, deno, mise, rustup, cargo + `cargo-install-update`, gem for their updates

---

## Platform Support

The OS is detected once per run (`uname -s`, `/etc/os-release`, and a `microsoft` kernel-release check for WSL2). Sections that don't apply to the platform are skipped silently.

| Platform | Cleanup | Updates |
|----------|---------|---------|
| macOS 14+ | All [cleanup categories](#cleanup-categories) | brew, mas, `softwareupdate` (minor updates only — major macOS upgrades are never auto-installed), language managers, skills, plugins |
| Linux (apt/dnf/pacman) | `~/.cache`, Trash, build artifacts, Docker, pipx (report), snap disabled revisions, unused flatpak runtimes; system package-cache cleanup surfaced as a **manual `sudo` step** | snap, flatpak, language managers, skills, plugins auto-applied; apt/dnf/pacman upgrades surfaced as **manual `sudo` steps** |
| WSL2 | Same as Linux | Same as Linux; winget/scoop/choco detected and reported, never run |

upkeep never runs `sudo`.

---

## Install

> **Status:** awaiting acceptance into the `claude-community` marketplace ([submission pending](https://claude.ai/settings/plugins/submit)). Until then, install directly from this repository as a personal marketplace.

In Claude Code, run these two slash commands:

```
/plugin marketplace add KyleNesium/upkeep
/plugin install upkeep@KyleNesium
```

The first command registers this repository as a marketplace named `KyleNesium`. The second installs the `upkeep` plugin from it.

Then run `/reload-plugins` (or restart Claude Code). The skills are available as `/upkeep`, `/upkeep:audit`, `/upkeep:cleandeep`, `/upkeep:cleanquick`, and `/upkeep:update`.

To update later (or let `/upkeep:update skills` do it):

```
/plugin update upkeep@KyleNesium
```

To remove:

```
/plugin uninstall upkeep@KyleNesium
/plugin marketplace remove KyleNesium
```

Alternative for local hacking: `git clone` this repo and load it with `--plugin-dir` (no marketplace registration needed):

```bash
git clone https://github.com/KyleNesium/upkeep ~/workspace/upkeep
claude --plugin-dir ~/workspace/upkeep/upkeep
```

---

## Usage

### Slash commands

```
# Mode selector — asks if no keyword detected
/upkeep                     # asks which mode
/upkeep deep                # full scan + cleanup
/upkeep quick               # caches + Trash sweep
/upkeep audit               # full scan, report only, no changes

# Direct sub-skill commands (bypass mode selector)
/upkeep:cleandeep           # full scan + cleanup
/upkeep:cleanquick          # caches + Trash sweep
/upkeep:audit               # report-only scan

# Update mode
/upkeep:update              # asks which update sub-mode
/upkeep:update audit        # check what's outdated, no changes
/upkeep:update skills       # AI skills + Claude Code plugins only
/upkeep:update packages     # package managers only
/upkeep:update all          # skills + plugins, then packages
```

### Trigger phrases

Claude loads the skill automatically for natural-language requests such as:

- "clean up my mac" / "free up disk space" / "quick cleanup"
- "audit my mac — what's taking up space?"
- "I just migrated from my old Mac, do a deep clean"
- "find orphaned app data"
- "update everything" / "update my AI skills" / "upgrade my packages" / "check for updates"

> [!TIP]
> Run `/upkeep audit` first on a new machine — it shows everything that's reclaimable without changing anything.

---

## How It Works

Cleanup and update share one shape: **discover → one approval gate → validated apply**, split across two turns so nothing runs in the same turn it was proposed.

**Cleanup** (`upkeep/skills/upkeep/scripts/clean.sh`):

1. `clean.sh discover <audit|quick|deep>` scans the filesystem read-only and writes a manifest of candidate items to `~/.claude/data/` (each with size, category, safety tier `safe` / `warn` / `report_only`, and a reason).
2. Claude renders the findings and asks once which categories to apply.
3. `clean.sh apply <manifest> [--drop=…]` refuses a manifest older than 15 minutes, then re-validates every item through `clean-validate.sh` before acting (see [Safety](#safety)). `report_only` items are never applied.

Orphaned app data is **discovered**, not looked up from a list: every `~/Library/Application Support/*` dir is matched against what's installed in `/Applications`, `~/Applications`, and Homebrew (casks + formulae). Unmatched dirs are reported as orphan candidates for you to investigate.

**Updates** (`upkeep/skills/update/scripts/update.sh`): `update.sh plan <mode>` runs discovery (`discover.sh`) and synthesis (`synthesize.sh` — semver classification, cross-manager compatibility warnings, ordering), and the gate is rendered from the plan. `update.sh apply <plan>` runs a hardcoded dispatcher over allowlisted tool ids, then post-flight checks and a pattern-table failure diagnoser (`diagnose.sh`).

---

## Cleanup Categories

| Category | Platform | Quick | Deep | Audit | What it targets | Tier |
|----------|----------|:-----:|:----:|:-----:|-----------------|------|
| Dev / app caches | all | ✓ | ✓ | ✓ | Every dir directly under `~/Library/Caches/` and `~/.cache/` (Claude's are excluded) | safe |
| Electron caches | macOS | ✓ | ✓ | ✓ | `Cache`, `Code Cache`, `GPUCache`, `Service Worker`, `CachedData`, `CachedExtension*`, `PersistentCache` under `~/Library/Application Support/` — skipped at apply if the app is running | safe |
| Trash | all | ✓ | ✓ | ✓ | `~/.Trash/*` | safe |
| Build artifacts | all | report | ✓ | ✓ | `node_modules`, `.venv`, `venv`, `.next`, `dist`, `build`, `target`, `__pycache__`, `.pytest_cache`, `.turbo` up to 4 levels under `~/workspace`, `~/dev`, `~/Developer`, `~/code`, `~/src`, `~/projects`, `~/repos` | safe in deep |
| Saved application state | macOS | | ✓ | ✓ | `~/Library/Saved Application State/*` | safe |
| Xcode | macOS | | ✓ | ✓ | DerivedData per project (safe); Archives (warn) | safe / warn |
| Homebrew | macOS | | ✓ | ✓ | `brew cleanup` (safe); `brew autoremove` orphan deps (warn) | safe / warn |
| Docker | all | | ✓ | ✓ | `docker system prune -f` (stopped containers, unused networks, dangling images, build cache), only if the daemon is up | warn |
| iOS backups | macOS | | ✓ | ✓ | Each device backup under `MobileSync/Backup/` | warn |
| Large files | macOS | | ✓ | ✓ | `.dmg`, `.pkg`, `.iso`, `.zip` in `~/Downloads` and `~/Desktop` (3 levels) | warn |
| LaunchAgents | macOS | | ✓ | ✓ | `~/Library/LaunchAgents/*.plist` whose program no longer exists (unloaded, then removed; `homebrew.mxcl.*` never touched) | warn |
| Shell config | macOS | | ✓ | ✓ | Dead `source` / path-`alias` lines in `~/.zshrc`, `.zprofile`, `.zshenv`, `.bash_profile`, `.bashrc`, `.profile` — edited with a backup, syntax-checked, auto-restored on failure | warn |
| Orphaned app data | macOS | | ✓ | ✓ | `~/Library/Application Support/*` with no matching installed app | report only |
| pipx tools | all | | ✓ | ✓ | Installed pipx tools, for you to uninstall manually | report only |
| snap revisions | Linux/WSL2 | | ✓ | ✓ | Disabled snap revisions | safe |
| flatpak runtimes | Linux/WSL2 | | ✓ | ✓ | Runtimes no installed app depends on | safe |
| System package cache | Linux/WSL2 | | ✓ | ✓ | `apt`/`dnf`/`pacman` cache cleanup — shown as a manual `sudo` command | manual |

**Tiers:** `safe` items are preselected at the gate; `warn` items carry a reason you see before approving; `report_only` items are listed but never deleted by upkeep.

---

## Modes

| Mode | Scans | Applies | Use it for |
|------|-------|---------|-----------|
| **Audit** | Everything in the table | Nothing — report only | Seeing where space went |
| **Quick** | Caches, Electron caches, Trash, build artifacts (report only) | After one approval | Routine monthly sweep |
| **Deep** | Everything in the table | After one approval | After a migration, or a periodic deep clean |
| **Update** | Outdated skills, plugins, packages | After one approval | Keeping tools current — see [Updating](#updating) |

Deletes are permanent (`rm -rf`), not moved to Trash — that's why the gate shows sizes and reasons first, and why audit mode exists.

---

## Updating

Say **"update everything"** in Claude Code, or run `/upkeep:update`.

| Sub-mode | What it does |
|----------|--------------|
| `update audit` | Show what's outdated across skills, plugins, and packages — no changes |
| `update skills` | `git pull` each repo in `~/.claude/skills/` and `~/.codex/skills/`; update outdated Claude Code plugins |
| `update packages` | macOS: brew, mas, `softwareupdate`. Linux: snap, flatpak (apt/dnf/pacman as manual `sudo` steps). All: npm globals, pipx, gems, uv, bun, deno, mise, rustup, cargo (with `cargo-install-update`) |
| `update all` | Skills + plugins first, then packages — one gate |

**What the gate shows.** Each upgrade is classified by semver bump, and known cross-manager risks are flagged (e.g. `brew:node` major ⇒ npm globals may need a rebuild; `brew:openssl` ⇒ native Ruby gems may need a recompile). When risks are flagged, the default option is **"apply all except flagged risks"**. The risk matrix (`upkeep/skills/update/compatibility.json`) is not exhaustive — an unflagged upgrade can still break something.

**Claude Code plugins.** Only plugins that are genuinely behind are flagged: the installed version in `installed_plugins.json` is compared with the version the marketplace declares. Add `--fresh` (e.g. `/upkeep:update all --fresh`) to `git fetch` each marketplace first. Apply fast-forwards the marketplace clone, then runs `claude plugin update <name>@<marketplace> --scope user --json`; anything the CLI can't finish falls back to a `/plugin update <name>` hand-off. Relaunch Claude Code to load new plugin versions.

**macOS system updates.** Each safe update is installed with `softwareupdate -i <label>` (never `-ia`); a major macOS upgrade is listed as a manual step and never auto-installed. System updates always carry a restart warning.

**Speed.** `brew update` is TTL-cached (1h; `UPKEEP_NO_CACHE=1` to bypass), so a warm run reaches the gate in a few seconds. `--advisor` adds opt-in changelog summaries and project-impact notes, which run after the gate.

**Config.** `~/.claude/data/upkeep-config.json` (override path with `UPKEEP_CONFIG`) accepts `shadow_ignore_dirs` (PATH dirs whose shadowing is intentional) and `system_ruby_gems` (default `false`: Apple's system Ruby gems are left alone).

**Self-update check.** `/upkeep` checks once a day whether a newer upkeep is available and asks whether to update first. The direct entrypoints (`/upkeep:audit`, `/upkeep:cleandeep`, `/upkeep:cleanquick`) skip the check. Disable it with `export UPKEEP_SKIP_UPDATE_CHECK=1`.

---

## Safety

| Rule | Detail |
|------|--------|
| One approval gate | Nothing is deleted, edited, or upgraded until you approve it; audit modes never change anything |
| Fresh plans only | A cleanup manifest older than 15 minutes (or future-dated) is refused — re-run discovery |
| Path containment | Every deletion target must resolve strictly under an allowed root (`~/Library/Caches`, `~/.cache`, `~/.Trash`, `~/Library/Logs`, Xcode/CoreSimulator dirs, `~/Library/Saved Application State`, `~/Library/Application Support`, `~/Library/LaunchAgents`, `~/Downloads`, `~/Desktop`, workspace dirs) — never a root itself |
| Protected paths | Never touches `~/.claude`, `~/.config/claude`, `~/Library/Application Support/Claude`, `~/Library/Keychains`, `~/Library/Preferences`, `~/Documents`, `/System`, `/Library`, `/Applications` |
| Symlinks | A symlinked target, or any symlinked directory on the way to it (below `$HOME`), is refused — a link can't redirect a delete into other data |
| Per-action shape | Electron deletes must be a known cache leaf; LaunchAgent deletes must be a single `.plist` in `~/Library/LaunchAgents` (never `homebrew.mxcl.*`); iOS backup deletes must be a single backup dir |
| Apply-time re-checks | Each item is re-validated immediately before acting: vanished → skip, became a symlink → skip, grew > 50% since discovery → skip, Electron app now running → skip |
| No sudo | Root-level commands (apt/dnf/pacman, system cache cleanup) are shown for you to run; upkeep never runs them |
| No model-authored commands | Commands are hardcoded per action in the scripts; plans and manifests carry data, never commands. Failure-diagnosis suggestions are text only and pass a denylist |
| Major OS upgrades | Never auto-installed |

---

## Privacy

- **Runs locally.** There is no upkeep server and no telemetry.
- **Network access happens only through the tools it runs:** `brew update`, `git pull` / `git fetch` for skills and marketplaces, `claude plugin update`, package-manager upgrades, and `softwareupdate`. Cleanup modes make no network requests. `--advisor` additionally fetches release notes from an allowlist of upstream hosts.
- **Local files it writes** (in `~/.claude/data/`, mode `0700`): update plans, cleanup manifests (consumed on apply), an update history file (`upkeep-history.json`), and optional prewarm manifests. Shell-config edits keep a backup next to the original (`~/.zshrc.upkeep-bak.<timestamp>`).

### Privacy Policy

**Effective date:** October 27, 2026

upkeep is a Claude Code plugin that runs entirely on your local machine. This policy explains what data the plugin accesses and how it is handled.

**Data collection:** None. upkeep has no telemetry, analytics, or crash reporting, and sends nothing to the plugin author or to Anthropic.

**Network use:** Update mode runs your package managers and `git`, which contact their own upstream sources (e.g. Homebrew, npm, GitHub). The optional `--advisor` flag fetches public release notes from an allowlisted set of upstream hosts. Cleanup modes make no network requests.

**Data access:** The plugin reads filesystem metadata (directory names, sizes, modification times) in standard locations — `~/Library/` and `/Applications/` on macOS, `~/.cache/` on Linux/WSL2, and project workspace directories on all platforms — plus your shell startup files (to find dead `source`/`alias` lines) and package-manager metadata. It does not read the contents of your documents or project files.

**Data storage:** Working files (plans, manifests, update history, optional prewarm manifests) are kept in `~/.claude/data/` with owner-only permissions. Findings are otherwise shown only in your Claude Code session.

**Data deletion:** With your explicit approval, upkeep removes files with standard commands (`rm`, `brew cleanup`/`autoremove`, `docker system prune`, `launchctl bootout`, `snap remove`, `flatpak uninstall --unused`). Removed files are deleted permanently, not moved to Trash.

**Third parties:** No data is shared with Anthropic, the plugin author, or any third party. The plugin has no server component.

**Changes:** Updates to this policy will be noted in the repository's commit history. The effective date above reflects the latest revision.

**Contact:** For questions about this policy, open an issue on [GitHub](https://github.com/KyleNesium/upkeep/issues).

---

## Architecture

```
upkeep/                                  # repo root (also the marketplace)
├── .claude-plugin/marketplace.json      # marketplace manifest
├── .github/
│   ├── workflows/release.yml            # tags + publishes a release when VERSION changes on main
│   ├── ISSUE_TEMPLATE/
│   └── PULL_REQUEST_TEMPLATE.md
├── upkeep/                              # the plugin
│   ├── .claude-plugin/plugin.json
│   ├── hooks/
│   │   ├── hooks.json                   # SessionStart hook registration
│   │   └── prewarm.sh                   # opt-in background discovery (off by default)
│   └── skills/
│       ├── upkeep/
│       │   ├── SKILL.md                 # /upkeep — mode selector, self-update gate, cleanup wrapper
│       │   ├── reference/               # cache paths, Apple system dirs, CLI dotdir ownership
│       │   └── scripts/
│       │       ├── clean.sh             # cleanup engine: discover / apply / prewarm
│       │       ├── clean-validate.sh    # path-safety validator (the deletion boundary)
│       │       └── lib/common.sh        # OS detection, canonicalization, shared helpers
│       ├── audit/SKILL.md               # /upkeep:audit      → clean.sh discover audit
│       ├── cleanquick/SKILL.md          # /upkeep:cleanquick → clean.sh discover/apply quick
│       ├── cleandeep/SKILL.md           # /upkeep:cleandeep  → clean.sh discover/apply deep
│       └── update/
│           ├── SKILL.md                 # /upkeep:update — two-turn wrapper
│           ├── compatibility.json       # cross-manager risk matrix
│           └── scripts/
│               ├── update.sh            # plan / apply orchestrator
│               ├── discover.sh          # outdated-tool discovery
│               ├── synthesize.sh        # semver, compat warnings, ordering
│               └── diagnose.sh          # failure pattern table
├── tests/
│   ├── test-clean-skill.sh
│   └── test-update-skill.sh
├── VERSION                              # bump on main → automatic GitHub release
├── CHANGELOG.md · CONTRIBUTING.md · SECURITY.md · LICENSE
```

Each `SKILL.md` is a thin two-turn wrapper: turn 1 runs discovery/plan and renders the gate, turn 2 runs apply and renders the report. All logic that touches the system lives in the bash scripts.

**Opt-in prewarm.** `touch ~/.claude/data/upkeep-prewarm-enabled` (or `export UPKEEP_PREWARM=1`) makes the SessionStart hook run `clean.sh prewarm` in the background, so a later `/upkeep quick` can reuse a fresh manifest instead of rescanning. Set the mode with `UPKEEP_PREWARM_MODE` (default `quick`).

---

## Contributing

1. Fork the repo and clone it under your workspace.
2. Change the script that owns the behavior — cleanup: `upkeep/skills/upkeep/scripts/`; updates: `upkeep/skills/update/scripts/`. Edit a `SKILL.md` only for gate/report rendering.
3. Add or update tests and run both suites with stock bash:
   ```bash
   /bin/bash tests/test-clean-skill.sh
   /bin/bash tests/test-update-skill.sh
   ```
4. Try it live with `claude --plugin-dir <your-clone>/upkeep`.
5. Open a PR describing what changed and why. Any change to `clean-validate.sh` needs regression tests that fail without it.

Ideas: Time Machine local snapshots, CoreSimulator cleanup, stale log cleanup, journald vacuum on Linux, live validation on a real Linux/WSL2 box.

---

## Version History

Full notes: [CHANGELOG.md](CHANGELOG.md).

| Version | Highlights |
|---------|-----------|
| 1.8.4 | Update no longer refuses on Linux/WSL2 with long device names (one shared `df -P` disk reading); disk-space refusals no longer reported as "up to date"; `--drop` expands from the plan; skill descriptions match the code |
| 1.8.3 | Plugin updates finish headlessly via `claude plugin update`; major macOS upgrades never auto-installed; `upkeep-config.json`; system-Ruby gems skipped by default; fixes `/upkeep:update skills` crash (broken since 1.6) |
| 1.8.2 | Validator refuses symlinked ancestors; Electron running-app check rewritten; non-numeric env overrides fall back to safe defaults |
| 1.8.1 | Audit-driven hardening: symlinked-target refusal, `--drop` fix, fail-safe disk guard, git argument-injection fix |
| 1.8 | Cleanup skills moved from prompt-orchestrated phases to the `clean.sh` engine + path-safety validator; opt-in prewarm hook |
| 1.7.1 | Automated releases on `VERSION` bump |
| 1.7 | Only genuinely-outdated Claude Code plugins flagged; "apply all except flagged risks" gate |
| 1.6 | Single-shot update flow ported to Linux and WSL2; sudo boundary |
| 1.5 | Two-turn update orchestrator; brew TTL cache; pattern-table diagnoser |
| 1.4 | Update discovery and synthesis moved from agents to bash |
| 1.3 | Opt-in AI update advisor (changelog reader, project impact) |

---

## Security

upkeep runs locally and modifies your filesystem. See [SECURITY.md](SECURITY.md) for the full security model, guarantees, and vulnerability reporting process.

---

## Test Coverage

**280 tests** across 2 automated test files (132 `clean` + 148 `update`). Run with
`bash tests/test-clean-skill.sh` and `bash tests/test-update-skill.sh` (both
pass under `/bin/bash`, macOS 3.2.57). The `clean` suite includes a pre-merge
security-regression set (shell-config command-injection, future-dated manifest
TTL bypass, quoted-path handling, symlink-target and symlinked-ancestor
deletion refusal, and non-numeric env-override fail-open) from
adversarial reviews; the `update` suite covers compat bump-gating and the
fail-safe disk-refuse guard.

As of v1.8 the cleanup skills (`audit`/`cleanquick`/`cleandeep`) are no longer
prompt-orchestrated — they are thin two-turn wrappers over a shared `clean.sh`
engine (`upkeep/skills/upkeep/scripts/{clean.sh,clean-validate.sh,lib/common.sh}`),
the same single-shot architecture `update` uses. The destructive path is moved
out of LLM prose into a tested, hardcoded path-safety validator.

### `clean.sh` cleanup engine (v1.8) — `tests/test-clean-skill.sh`

| Area | Tests | What's covered |
|------|-------|----------------|
| Path-safety validator | ~17 | Containment under SAFE_ROOTS; PROTECTED denylist override; per-action shape (electron cache-leaf, launchagent single-plist + homebrew.mxcl exclusion, mobilesync per-backup); attack battery (traversal, symlink escape, symlinked ancestor → other app / other safe root, outside-roots, leading-dash, spaces); symlinked `$HOME` still validates; >256-char path preserved |
| Apply re-validation | ~11 | 15-min manifest TTL refusal (also with non-numeric `UPKEEP_CLEAN_TTL`); TOCTOU vanished / type-swap / size-drift skip; ancestor swapped to symlink after discover → skipped, other app's cache kept; non-numeric `UPKEEP_CLEAN_DRIFT_PCT` doesn't abort; report_only never deleted; `--drop` category exclusion; per-item isolation; manifest consumed |
| Discover engine | ~13 | audit/quick/deep modes; needs_approval; dual path repr; atomic manifest write + created_at; build-artifacts report_only in quick; Claude cache excluded; xcode, ios_backup, large_file, orphan-app-data (report_only) sections |
| Non-path actions | ~5 | brew cleanup/autoremove + docker prune discover (PATH-stubbed); apply invokes the real command; pipx tool-name metachar rejection |
| Linux/WSL2 branch | ~4 | apt cache as sudo manual step; snap disabled-revision → snap_remove; flatpak unused → flatpak_unused; snap_remove identifier validation (via OS-override seam) |
| Shell-config editor | ~8 | dead source/path-alias lines removed; conditional / `&&` / live lines kept; cp backup created; result passes `zsh -n` (edit + validate + auto-restore) |
| Eager-discovery prewarm | ~9 | prewarm writes a stable manifest; discover reuses within TTL; `UPKEEP_NO_REUSE` + stale-TTL + corrupt `created_at` force a fresh scan; hook no-op when disabled; plugin.json/hooks.json valid |
| Wrapper + umbrella structure | ~22 | All three wrappers reference the engine, version 1.8.0, no broad `Bash(rm *)`/`Edit` grants; audit never applies; quick/deep two-turn; umbrella routes to clean.sh with the self-update gate preceding cleanup execution |
| Shared helpers | ~18 | `_sanitize_text` caps free-text/strips control chars (never paths); `_detect_os` override seam; `_clean_lexnorm` (`//`, `.`, `..`, relative → empty); `_numeric_or` (non-numeric/negative/overflow → default, no octal, epoch passes); `_read_repo_version` (blank `VERSION` falls through to `plugin.json`, `VERSION` wins, neither → empty) |
| Running-app detection | 9 | Electron guard via `_clean_app_running` on a fixture process list: helper / main binary / >15-char / case-insensitive matches; vendor dir → app name (BraveSoftware); `Code` ≠ `codex`/`PasscodeSettings`; regex chars literal; real `ps` never self-matches |

### `update` skill (v1.1–v1.8.4) — `tests/test-update-skill.sh`

| Area | Tests | What's covered |
|------|-------|----------------|
| Syntax | 4 | `bash -n` across all four `scripts/*.sh` |
| `update.sh plan` contract | ~6 | Valid JSON, plan_file (non-symlink), audit short-circuit, summary shape |
| Security invariants | ~4 | No `command`/`preconditions` in plan JSON or stored file, `DATA_DIR` 0700 |
| Mode filters | 4 | `skills` plan succeeds on the macOS and Linux native stubs; `skills` excludes package groups; `packages` excludes plugin-update steps |
| `diagnose.sh` validation | ~7 | Tool allowlist, numeric rc, kind, path-traversal / non-absolute / metachar log paths |
| `diagnose.sh` denylist | ~13 | Destructive-command filter (rm -rf, curl\|sh, eval, dd of=/dev, …) vs allowed fixes |
| `update.sh apply` contract | ~5 | Empty/`--drop` CSV safety, report JSON shape, plan-file cleanup |
| `jq`-missing contract | 2 | `{"error":…}` to stdout when `jq` absent |
| Linux/WSL2 fast path (v1.6) | ~29 | OS-detection seam, `discover_native_linux` shape, dnf exit-100 + Obsoleting-section exclusion, apt from-less line parsing, flatpak app-ID column, WSL2 `winget.exe` detection, sudo boundary (apt → manual steps not ordered_groups), snap/flatpak auto-apply, allowlist rejection of sudo managers, Linux diagnose patterns, macOS regression guard |
| Plugin updates + risk gate (v1.7) | 30 | Outdated-plugin detection (installed_plugins.json vs marketplace version: outdated flagged, current/absent skipped, real-version-vs-marketplace-"unknown" not mis-flagged, version resolved from plugin's own plugin.json when the marketplace omits it incl. `source` subdir + `./` root, `..`/absolute `source` path-traversal blocked, version surfacing, `plugins_outdated` count); `--fresh` upstream-manifest fetch (stale local clone hides update without it, detected with it); `risk_categories` computation (cause→category mapping, empty-when-no-warning, intersection-with-groups guard); plan-contract field/type guards; plan-output surfacing; packages-mode plugin-group exclusion; apply-phase marketplace pull (ff-only success + HEAD advance, path-containment refusal, `--drop=plugins` skip-but-still-hand-off) |
| Headless plugin update (v1.8.3) | 8 | Apply runs `claude plugin update <name>@<marketplace> --scope user --json` (exact argv asserted via a stub CLI); success → `updated` + relaunch-only note; CLI failure → `failed` + `/plugin update` hand-off kept; no CLI → `no-cli` + hand-off; malformed plugin id (`;`, spaces) refused and never passed to the CLI |
| macOS updates + PATH shadows (v1.8.3) | 6 | Stub `softwareupdate`/`sw_vers`: bare labels, Recommended major upgrade excluded into `major_upgrades[]`, `restart_required` ignores it, `macos-major` manual step; apply runs one `softwareupdate -i <label>` per safe label and refuses `-ia` / metacharacter labels; PATH dir listed twice → one shadow row (macOS + Homebrew only) |
| Config, system Ruby, dirty (v1.8.3) | 9 | System-Ruby gems skipped by default (no group/count/warning, `system-ruby-skipped` step) and planned when opted in; `upkeep-config.json` `system_ruby_gems` reaches discovery, absent file → default; `shadow_ignore_dirs` suppresses that dir's shadow rows; untracked-only skill repo not dirty, tracked edit still dirty. Suite sandboxes `UPKEEP_DATA_DIR`/`UPKEEP_CONFIG` |
| Disk, refusal, detached, drop (v1.8.4) | 15 | Stub GNU `df` that wraps long device names (and one with spaces in the device name): discovery and `clean.sh disk` read the real free/total via `df -P`; low disk → plan `refused: true`, `needs_approval: false`, `disk-refuse` warning; SKILL.md refusal step precedes the nothing-to-do step; detached skill repo excluded from group count and `category_counts`, surfaced as `skill-detached`; skills predicate defined once; `--drop=language` expands from the plan's `tools` (npm stub never invoked, with a control run that does invoke it); no hardcoded group map |

### Skill-level coverage (live invocation)

| Command | What's validated |
|---------|-----------------|
| `/upkeep` | Mode selection routing, keyword detection, self-update gate before cleanup execution (v1.8) |
| `/upkeep:cleandeep` | Two-turn wrapper over `clean.sh discover deep` → gate → apply (v1.8) |
| `/upkeep:cleanquick` | Two-turn wrapper over `clean.sh discover quick`; build artifacts report-only (v1.8) |
| `/upkeep:audit` | One-turn `clean.sh discover audit`, zero mutations, never truncates (v1.8) |
| `/upkeep:update` (Linux / WSL2, v1.6) | Single-shot fast path: OS-aware discovery, snap/flatpak auto-apply, apt/dnf/pacman as manual sudo steps, WSL2 Windows audit-only, single approval gate |
| `/upkeep:update` (macOS, v1.1) | Parallel scouts, compatibility synthesizer, single approval gate, parallel apply, post-flight (brew doctor, PATH shadow, deprecation aggregator), history-tuned ETA |
| `/upkeep:update` (security, v1.2) | Hardcoded apply dispatcher (no `eval`), allowlisted tool ids, denylist + length-cap discovery sanitization, exact-match remote URL validation, first-encounter trust gate for third-party skill repos, Discover/Approve/Apply turn separation, atomic + `flock`-serialized history writer |
| `/upkeep:update` (regression-fix, v1.2.2) | macOS skills apply phase actually pulls trusted git skill repos (was a silent no-op since v1.2.0); skills-scout no longer fetches from untrusted remotes; router Update Mode redirects to `/upkeep:update` instead of duplicating its logic |
| `/upkeep:update` (advisor, v1.3) | `changelog-reader` allowlisted-host fetches, `project-impact` manifest walk under `$HOME` workspace roots, `failure-diagnoser` per-tool log slicing with text-only fix surfaces, destructive-command denylist on diagnoser output |
| `/upkeep:update` (fast discovery, v1.4) | `scripts/discover.sh` four-section parallel discovery (~15s vs v1.3's ~90s), `scripts/synthesize.sh` deterministic plan synthesis (~300ms), `brew update` inside discovery for accurate outdated lists, enrichment gating on majors / medium+ compat edges only |
| `/upkeep:update` (single-shot, v1.5) | `scripts/update.sh plan` + `scripts/update.sh apply` two-turn flow, `brew update` TTL cache (`formula.jws.json` mtime, 1h default), `scripts/diagnose.sh` 8-pattern failure table replacing LLM agent, opt-in `--advisor` post-gate enrichment, canonical-path skill containment, TOCTOU-safe plan-file write (`mktemp -d` + atomic rename), `DATA_DIR` mode 0700, TSV-row validation in `diagnose.sh`, JSON-to-stdout error contract on missing `jq`, bash 3.2 compatibility (no `declare -A`) |
| `/upkeep:update` (Linux/WSL2 port, v1.6) | One OS-aware orchestrator for macOS/Linux/WSL2, `discover_native_linux` (apt/dnf/pacman audit + snap/flatpak + WSL2 Windows managers), sudo boundary (apt/dnf/pacman excluded from dispatcher allowlist → manual steps only), snap/flatpak auto-apply, `os.type`-branched synthesizer, 4 new Linux diagnose patterns, `UPKEEP_OS_OVERRIDE`/`UPKEEP_PKG_MGR_OVERRIDE` test seam, legacy v1.0 sequential flow retired |
| `/upkeep:update` (plugins + risk gate, v1.7) | Claude Code plugin outdated detection (`installed_plugins.json` vs marketplace `marketplace.json` version) — only genuinely-behind plugins flagged; marketplace git source refreshed `--ff-only` (canonical-path containment to `~/.claude/plugins/marketplaces/*`, deduped, dirty/detached skipped); cache reinstall handed off as a `/plugin update` + relaunch manual step (no headless path — never rewrites `installed_plugins.json`); "apply all except flagged risks" gate option + explicit confirmation for applying flagged risks; standing compatibility disclaimer; `UPKEEP_INSTALLED_PLUGINS`/`UPKEEP_PLUGIN_MARKETPLACES` test seams |
| `/upkeep:update` (headless plugin update, v1.8.3) | Apply finishes outdated-plugin updates via `claude plugin update` (no `-y`; plugin id validated; `UPKEEP_CLAUDE_BIN` test seam) with per-plugin `updated[]` status and a `/plugin update` fallback; fixes `plan skills` crashing on an invalid `--argjson` native stub (broken since v1.6); major macOS upgrades kept out of apply (`softwareupdate -i <label>` per planned update instead of `-ia`); PATH-shadow rows deduped; `upkeep-config.json` (`shadow_ignore_dirs`, `system_ruby_gems`); system-Ruby gems skipped by default; untracked files don't count as dirty |

---

## License

[MIT](LICENSE)
