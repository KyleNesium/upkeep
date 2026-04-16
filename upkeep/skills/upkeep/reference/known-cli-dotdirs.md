# Known CLI Dotdirs

Mapping of common ~/.<dir> directories to their owning CLI tools. Used to avoid false-positive orphan flags — these are NOT orphans even though they have no .app bundle.

## Valid Tool Dotdirs

| Dotdir | Owning Tool | Notes |
|--------|-------------|-------|
| `~/.rustup/` | rustup | Rust toolchain manager |
| `~/.cargo/` | cargo | Rust package manager |
| `~/.nvm/` | nvm | Node version manager |
| `~/.fnm/` | fnm | Fast Node Manager |
| `~/.pyenv/` | pyenv | Python version manager |
| `~/.rbenv/` | rbenv | Ruby version manager |
| `~/.volta/` | volta | JavaScript tool manager |
| `~/.asdf/` | asdf | Multi-language version manager |
| `~/.mise/` | mise / rtx | Multi-language version manager |
| `~/.sdkman/` | SDKMAN! | JVM SDK manager |
| `~/.deno/` | deno | Deno JS/TS runtime |
| `~/.swiftpm/` | Swift PM | Swift Package Manager |
| `~/.pub-cache/` | Dart/Flutter | Dart package cache |
| `~/.terraform.d/` | Terraform | Provider configs and plugins |
| `~/.ansible/` | Ansible | Plugins and inventory |
| `~/.helm/` | Helm | Kubernetes package manager |
| `~/.kube/` | kubectl / Kubernetes | K8s config |
| `~/.aws/` | AWS CLI | Credentials and config |
| `~/.gcloud/` | Google Cloud SDK | Credentials and config |
| `~/.pulumi/` | Pulumi | IaC tool stacks and plugins |
| `~/.heroku/` | Heroku CLI | Credentials and plugins |
| `~/.fly/` | Fly.io CLI | Credentials |
| `~/.vercel/` | Vercel CLI | Credentials |
| `~/.netlify/` | Netlify CLI | Credentials |
| `~/.dagger/` | Dagger | CI/CD runner config |
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
| `~/.windsurf/` | Windsurf IDE | Windsurf in /Applications |
| `~/.vagrant.d/` | Vagrant | `command -v vagrant` |
| `~/.phpls/` | PHP Language Server | `command -v composer` |
