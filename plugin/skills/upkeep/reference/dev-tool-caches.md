# Dev Tool Caches

Known dev tool cache locations. Check each, report size, skip any that don't exist.

| Tool | Location | Clear Command |
|------|----------|---------------|
| npm | `~/.npm/_cacache` | `npm cache clean --force` |
| bun | `~/.bun/install/cache` | `rm -rf ~/.bun/install/cache` |
| yarn | `~/.yarn/cache` | `yarn cache clean` |
| pnpm | `~/.local/share/pnpm/store` | `pnpm store prune` |
| uv | `~/.cache/uv/` | `rm -rf ~/.cache/uv/` |
| pip | `~/Library/Caches/pip/` | `pip cache purge` |
| puppeteer | `~/.cache/puppeteer/` | `rm -rf ~/.cache/puppeteer/` |
| Go build | `~/Library/Caches/go-build/` | `go clean -cache` |
| Go modules | `~/go/pkg/mod/` | `go clean -modcache` |
| cargo | `~/.cargo/registry/cache/` | `rm -rf ~/.cargo/registry/cache/` |
| Homebrew | `~/Library/Caches/Homebrew/` | `brew cleanup` |
| pre-commit | `~/.cache/pre-commit/` | `rm -rf ~/.cache/pre-commit/` |
| CocoaPods | `~/Library/Caches/CocoaPods/` | `pod cache clean --all` |
| Gradle | `~/.gradle/caches/` | `rm -rf ~/.gradle/caches/` |
| Maven | `~/.m2/repository/` | `rm -rf ~/.m2/repository/` |
