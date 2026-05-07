# Phase 7 Context — Parallel Discovery Agents

## Goal

Replace the sequential `Step 1` + `Step 2` discovery in `/upkeep:update` with
four parallel sub-agents. Each scout owns a domain and emits structured JSON
that Phase 8 (synthesizer) consumes.

## Non-goals

- Not adding new discovery surfaces beyond what v1.0 already covers (except
  codex git skills — see R12).
- Not changing the apply flow — that's Phase 9.
- Not touching Linux/WSL2 paths — they keep the v1.0 sequential code.

## Inputs

- `$OS_TYPE` from existing OS detection block (already in SKILL.md).
- HOME directory layout assumptions (`~/.claude/skills/`, `~/.codex/skills/`,
  `~/.claude/plugins/cache/`).

## Outputs

A single JSON document committed to a transient discovery file (or carried
in-context for the synthesizer agent), shaped:

```json
{
  "schema_version": "1",
  "os": {"type": "macos", "distro": "macos", "arch": "arm64"},
  "skills": {
    "git_repos": [
      {
        "name": "gstack",
        "path": "/Users/kyle/.claude/skills/gstack",
        "branch": "main",
        "current_version": "1.5.1.0",
        "commits_behind": 31,
        "newest_commit_subjects": ["v1.27.1.0 fix: ...", "..."],
        "breaking_lines": ["..."],
        "dirty_files": [".feature-prompted-..."],
        "detached": false,
        "remote_ok": true
      }
    ],
    "managed": [
      {"name": "upkeep", "manager": "claude-code-plugin", "version": "1.0.6", "update_command": "/plugin update upkeep"}
    ],
    "info": {"claude_plugins": 10, "codex_skills_total": 16, "codex_skills_git": 4}
  },
  "native": {
    "brew": {
      "installed": true,
      "outdated": [
        {"name": "node", "from": "20.18.1", "to": "22.10.0", "bump": "major"},
        {"name": "python@3.13", "from": "3.13.1", "to": "3.13.2", "bump": "patch"}
      ]
    },
    "softwareupdate": {"installed": true, "updates": [], "restart_required": false},
    "mas": {"installed": false}
  },
  "language": {
    "npm":    {"installed": true, "outdated": [{"name": "npm", "from": "11.12.1", "to": "11.14.0", "bump": "minor"}]},
    "pipx":   {"installed": true, "tools":   [{"name": "semgrep", "from": "1.159.0", "to": "1.161.0", "bump": "minor"}]},
    "gems":   {"installed": true, "system_ruby": true, "ruby_version": "2.6", "outdated": [{"name": "bundler", "from": "1.17.2", "to": "4.0.11", "bump": "major"}]},
    "uv":     {"installed": true, "current": "0.9.7"},
    "bun":    {"installed": true, "current": "1.3.9"},
    "deno":   {"installed": false},
    "rustup": {"installed": false},
    "cargo":  {"installed": false},
    "mise":   {"installed": false}
  },
  "shadow": {
    "duplicates": [
      {"binary": "gemini", "primary": "/Users/kyle/.superset/bin/gemini", "shadowed": ["/opt/homebrew/bin/gemini"]}
    ],
    "broken_symlinks": []
  },
  "disk": {"free_gb": 124, "warn_threshold_gb": 10, "refuse_threshold_gb": 5}
}
```

## Constraints

- All four scouts must run in a single assistant tool-use block (true
  parallelism).
- Each scout prompt must be self-contained (no shared context).
- Scout failures must produce a partial JSON with an `errors[]` array — never
  block the run.
- `system_ruby: true` is set when `ruby --version` resolves to system Ruby
  (`/usr/bin/ruby` and version starts with `2.`). This drives R8.

## Open questions resolved

- **JSON storage**: in-context only. Don't write to disk. Synthesizer agent
  receives it as part of its prompt.
- **shadow detection scope**: only run after the brew outdated list is known
  — focus on binaries from soon-to-upgrade brew formulas (saves cycles).

## Risks

- Agent calls have 5-10s overhead each. Four parallel agents = single ~10s
  hit instead of 11 sequential ~3s round-trips. Net win on populated
  machines, neutral on empty machines. Acceptable.
- JSON schema drift between scouts and synthesizer — pin schema_version and
  reject mismatched payloads.
