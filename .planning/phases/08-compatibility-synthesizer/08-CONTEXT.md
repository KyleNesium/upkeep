# Phase 8 Context — Compatibility Synthesizer

## Goal

A single Agent that consumes the JSON from Phase 7 scouts and emits an
ordered apply plan with risk flags, ETA, and a compact summary.

## Why an agent and not inline bash

- Cross-manager dependency reasoning is naturally LLM-shaped (e.g., "if
  brew is upgrading openssl 3.3 → 3.4, ruby gems with native extensions
  built against 3.3 may break — flag nokogiri, openssl, sassc, etc.").
- Future-proof: as new managers and edge cases appear, prompt edits beat
  shell-case-statement edits.
- Output is structured JSON consumed by Phase 9, so the agent has a
  testable contract.

## Inputs

JSON payload from Phase 7 (see 07-CONTEXT.md schema).
Plus: a static compatibility matrix file at
`upkeep/skills/update/compatibility.json`:

```json
{
  "schema_version": "1",
  "edges": [
    {"from": "brew:node",     "to": "npm-globals",  "reason": "native modules built against node ABI"},
    {"from": "brew:node",     "to": "bun-globals",  "reason": "shared node-modules tree"},
    {"from": "brew:python@*", "to": "pipx",         "reason": "pipx venvs use brew python"},
    {"from": "brew:python@*", "to": "uv",           "reason": "uv installs may target brew python"},
    {"from": "brew:openssl@*","to": "gems-native",  "formulas": ["nokogiri", "openssl", "sassc"], "reason": "native ext linked against openssl"},
    {"from": "brew:ruby",     "to": "gems-user",    "reason": "user gems live under brew ruby gem dir"},
    {"from": "brew:icu4c",    "to": "gems-native",  "formulas": ["charlock_holmes"], "reason": "linked against icu4c"},
    {"from": "brew:postgresql@*", "to": "gems-native", "formulas": ["pg"], "reason": "linked against pg client"}
  ]
}
```

## Outputs

```json
{
  "schema_version": "1",
  "plan": {
    "summary": {
      "skills_to_update": 1,
      "categories_to_upgrade": 5,
      "major_bumps": 3,
      "eta_minutes_p50": 22,
      "eta_minutes_p90": 38
    },
    "warnings": [
      {"severity": "high", "message": "Refusing to run: only 4 GB free disk space"}
    ],
    "manual_steps": [
      {"label": "upkeep self-update", "command": "/plugin update upkeep"},
      {"label": "PATH shadow", "command": "Move /opt/homebrew/bin before ~/.superset/bin in PATH or rename your local gemini wrapper"}
    ],
    "ordered_groups": [
      {
        "id": "skills",
        "tools": ["gstack"],
        "parallelism": "serial",
        "rationale": "Few skills; trivial wall time."
      },
      {
        "id": "brew",
        "tools": ["brew"],
        "parallelism": "exclusive",
        "rationale": "Touches downstream language toolchains; must finish before language ecosystems."
      },
      {
        "id": "language",
        "tools": ["npm", "pipx", "gems", "uv", "bun"],
        "parallelism": "parallel",
        "rationale": "Independent ecosystems; can run concurrently after brew."
      },
      {
        "id": "stores",
        "tools": ["mas", "macOS"],
        "parallelism": "serial",
        "rationale": "macOS update may force restart; run last."
      }
    ],
    "tool_specs": {
      "gstack": {
        "kind": "skill",
        "command": "git -C /Users/kyle/.claude/skills/gstack pull --ff-only origin main",
        "preconditions": [],
        "current_version": "1.5.1.0",
        "target_version": "1.27.1.0",
        "bump": "major",
        "breaking": ["v1.16.0.0 feat: tunnel allowlist 17→26", "..."]
      },
      "brew": {
        "kind": "package_manager",
        "command": "brew upgrade",
        "preconditions": ["brew update >/dev/null"],
        "outdated_count": 36,
        "major_bumps": ["node 20 → 22", "python@3.13 3.13.1 → 3.13.2 (patch — not major)"],
        "downstream_effects": ["npm-globals (rebuild)", "pipx", "gems-native: nokogiri (openssl 3.3 → 3.4)"]
      },
      "gems": {
        "kind": "package_manager",
        "command": "gem update --user-install",
        "preconditions": [],
        "rationale_for_flag": "system Ruby 2.6 detected; --user-install avoids sudo"
      }
    }
  }
}
```

## Constraints

- Synthesizer is one Agent call, sequential (after the four scouts).
- Output must validate against the schema_version "1" contract or Phase 9
  refuses to apply.
- Time estimate: read median wall time per category from
  `~/.claude/data/upkeep-history.json` if present; fall back to bake-in
  defaults (brew: 1.5 min/package, gems: 0.3 min/gem, npm globals: 1
  min/package, pipx: 0.5 min/tool).

## Risks

- Synthesizer hallucinates a downstream effect that doesn't exist —
  mitigation: the matrix file is the source of truth; agent prompt says
  "do not invent edges not in compatibility.json."
- Synthesizer truncates or reformats JSON — mitigation: the agent prompt
  includes a strict schema example and instruction to emit JSON only.
- Schema drift over time — mitigation: reject if `schema_version`
  mismatches; bump on every breaking change.
