# Known CLI Dotdirs

Mapping of common ~/.<dir> directories to their owning CLI tools. Used to avoid false-positive orphan flags — these are NOT orphans even though they have no .app bundle.

## Valid Tool Dotdirs

| Dotdir | Owning Tool | Notes |
|--------|-------------|-------|
| `~/.rustup/` | rustup | Rust toolchain manager |
| `~/.cargo/` | cargo | Rust package manager |
| `~/.nvm/` | nvm | Node version manager |
| `~/.pyenv/` | pyenv | Python version manager |
| `~/.rbenv/` | rbenv | Ruby version manager |
| `~/.volta/` | volta | JavaScript tool manager |
| `~/.sdkman/` | SDKMAN! | JVM SDK manager |
| `~/.local/` | various | XDG local data/bin |
| `~/.config/` | various | XDG config |
| `~/.cache/` | various | XDG cache |
| `~/.gradle/` | Gradle | Build tool |
| `~/.m2/` | Maven | Build tool |
| `~/.npm/` | npm | Package manager cache |
| `~/.bun/` | bun | JavaScript runtime |
| `~/go/` | Go | Default GOPATH (no dot prefix) |

## Common Orphan Dotdirs

These dotdirs typically indicate an uninstalled tool. Verify the tool is absent before flagging.

| Dotdir | Was For | Check |
|--------|---------|-------|
| `~/.docker/` | Docker Desktop | `command -v docker` |
| `~/.codeium/` | Windsurf/Codeium | Windsurf in /Applications |
| `~/.cursor/` | Cursor IDE | Cursor in /Applications |
| `~/.eclipse/` | Eclipse IDE | Eclipse in /Applications |
