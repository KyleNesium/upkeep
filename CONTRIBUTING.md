# Contributing to upkeep

## How skills work

upkeep is a Claude Code plugin. Each skill is a `SKILL.md` — a structured prompt
that Claude follows when the command is invoked. There are no binaries, no build
step, no test runner. Changes take effect immediately.

**Entry points:**

| Command | File |
|---------|------|
| `/upkeep` | `plugin/skills/upkeep/SKILL.md` |
| `/upkeep:cleandeep` | `plugin/skills/cleandeep/SKILL.md` |
| `/upkeep:cleanquick` | `plugin/skills/cleanquick/SKILL.md` |
| `/upkeep:audit` | `plugin/skills/audit/SKILL.md` |
| `/upkeep:update` | `plugin/skills/update/SKILL.md` |

Reference tables (cache paths, system dirs, CLI dotdirs) live in
`plugin/skills/upkeep/reference/` and are read by the skill at runtime.

## Making a change

1. Fork the repo and clone it
2. Point Claude Code at your fork (see README Install section)
3. Edit the relevant `SKILL.md`
4. Test by invoking the affected command in Claude Code
5. Open a PR with what changed and why

## Testing checklist

- [ ] Mode selection works (correct keyword → correct mode)
- [ ] All referenced phase numbers match the skill body
- [ ] Safety rules are enforced (no sudo, no silent deletion, sizes shown first)
- [ ] Update check nudge fires correctly (test with a behind commit)
- [ ] Reference file paths resolve (use `${CLAUDE_SKILL_DIR}/` prefix correctly)
- [ ] Sub-skill path depth: all skills use `../../..` for repo root (3 levels up from their `plugin/skills/<name>/` dir)

## Path depth reference

`CLAUDE_SKILL_DIR` points to the directory containing the loaded `SKILL.md`:

| Skill file | CLAUDE_SKILL_DIR | Repo root | Reference dir |
|-----------|-----------------|-----------|---------------|
| `plugin/skills/upkeep/SKILL.md` | `plugin/skills/upkeep/` | `../../..` | `./reference/` |
| `plugin/skills/cleandeep/SKILL.md` | `plugin/skills/cleandeep/` | `../../..` | `../upkeep/reference/` |
| `plugin/skills/audit/SKILL.md` | `plugin/skills/audit/` | `../../..` | `../upkeep/reference/` |
| `plugin/skills/cleanquick/SKILL.md` | `plugin/skills/cleanquick/` | `../../..` | `../upkeep/reference/` |
| `plugin/skills/update/SKILL.md` | `plugin/skills/update/` | `../../..` | `n/a` |

## Ideas for contributions

- New cleanup phases (Time Machine local snapshots, Rosetta 2 cache, Swift package cache)
- Smarter orphan detection heuristics
- Additional known CLI dotdirs in `reference/known-cli-dotdirs.md`
- Additional dev tool caches in `reference/dev-tool-caches.md`

## Commit style

Follow the existing `<type>: <description>` format. Types: `feat`, `fix`,
`docs`, `chore`. Keep the description under 72 characters.
