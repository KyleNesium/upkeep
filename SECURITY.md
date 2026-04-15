# Security Policy

upkeep runs locally and modifies your filesystem. This document describes the security model, the guarantees the skill makes, and how to report issues.

## Reporting a Vulnerability

If you find a way upkeep could damage a user's system, leak data, or bypass its own safety rules:

1. **Do not open a public issue.**
2. Report via [GitHub Security Advisory](https://github.com/KyleNesium/upkeep/security/advisories/new).
3. Expect an acknowledgment within 7 days.

Only the latest version receives security updates.

## Security Model

### Threat model

upkeep is a Claude Code skill that runs shell commands on the user's Mac to reclaim disk space. Its threat surface is:

- Accidentally deleting user data (primary risk — higher-impact than remote attackers for a local tool)
- Acting on stale assumptions (app looks uninstalled but is actually running; dotfile is orphaned but is actually used by a rarely-invoked binary)
- Leaking filesystem metadata in reports that the user then pastes into other contexts

upkeep does **not** defend against a malicious local user on the same machine, against a compromised Claude Code binary, or against a compromised shell environment. A user who can invoke the skill has already granted execution access to Claude Code.

### Guarantees

**Local only.** upkeep makes no network calls. All operations use standard macOS and Homebrew commands against the local filesystem.

**No telemetry.** upkeep does not collect, log, or transmit any data about the user's system, the findings it produces, or its own execution.

**No sudo.** upkeep never runs `sudo` or elevates privileges. Operations that would require root are surfaced to the user as shell commands to run manually, with an explanation of what they do.

**Approval required for destructive operations.** Every removal is gated behind an explicit user prompt that names what will be removed and its size. The `audit` mode disables removal entirely.

**Protected directories.** upkeep will not modify, list for removal, or touch:
- `~/.claude/` and `~/Library/Application Support/Claude/`
- `~/Library/Keychains/`, `~/Library/Preferences/`, `~/Library/Mail/`
- Any directory starting with `com.apple.*`
- Any data directory for an app currently present in `/Applications/`

**Size reporting before removal.** Every candidate is sized with `du` and reported to the user before the removal prompt.

**LaunchAgent safety.** LaunchAgents are unloaded via `launchctl` before their plist files are deleted, preventing crash-loops of orphaned services.

**Shell config edits are validated.** Before any edit to `~/.zshrc`, `~/.bashrc`, etc., upkeep creates a timestamped backup (`.upkeep-bak.YYYYMMDD-HHMMSS`). After each edit, the file is validated with `zsh -n`. Syntax failure auto-restores from backup and aborts further edits.

**Conditional blocks are never edited.** Lines inside `if`/`fi`, `case`/`esac`, or containing `&&`/`||` operators are reported as findings only. These typically gate on env/host/OS and removing them silently breaks workflows.

### Non-guarantees

**No filesystem snapshot/rollback.** upkeep relies on Trash (where applicable) and Homebrew's own cleanup guarantees. Permanently deleted items (e.g., `brew cleanup`, `rm` on non-Trash paths) are not recoverable by the skill itself. Time Machine or equivalent is the user's responsibility.

**No cross-user safety.** upkeep operates on the invoking user's `$HOME`. If run as a different user, it will target that user's files.

**No runtime sandbox.** upkeep runs with whatever permissions Claude Code has. Users who have granted broad `allowedTools` to Claude Code grant upkeep the same.

## Data Handling

upkeep reads filesystem metadata (directory names, file sizes, modification times) in standard macOS locations (`~/Library/`, `~/.cache/`, `/Applications/`, `~/Library/LaunchAgents/`, project workspace directories). File **contents** are not read except for shell config files the user has explicitly approved editing.

No data is stored by upkeep itself. Findings live in the Claude Code conversation and are discarded when the session ends.

## Responsible Disclosure

Thank you for helping keep upkeep safe. Credit for valid reports is given in the release notes unless you request anonymity.
