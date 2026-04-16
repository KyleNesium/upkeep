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
| Playwright | `~/Library/Caches/ms-playwright/` | `rm -rf ~/Library/Caches/ms-playwright/` |
| Go build | `~/Library/Caches/go-build/` | `go clean -cache` |
| Go modules | `~/go/pkg/mod/` | `go clean -modcache` |
| cargo | `~/.cargo/registry/cache/` | `rm -rf ~/.cargo/registry/cache/` |
| Homebrew | `~/Library/Caches/Homebrew/` | `brew cleanup` |
| pre-commit | `~/.cache/pre-commit/` | `rm -rf ~/.cache/pre-commit/` |
| CocoaPods | `~/Library/Caches/CocoaPods/` | `pod cache clean --all` |
| Gradle | `~/.gradle/caches/` | `rm -rf ~/.gradle/caches/` |
| Maven | `~/.m2/repository/` | `rm -rf ~/.m2/repository/` |
| Dart/Flutter | `~/.pub-cache/` | `flutter pub cache clean` or `rm -rf ~/.pub-cache/` |
| Swift PM | `~/.swiftpm/xcode-data/` | `rm -rf ~/.swiftpm/xcode-data/` |
| Terraform | `~/.terraform.d/plugin-cache/` | `rm -rf ~/.terraform.d/plugin-cache/` |
| asdf | `~/.asdf/installs/` | `rm -rf ~/.asdf/installs/<lang>/<old-version>` |
| volta | `~/.volta/tools/image/` | `volta uninstall <tool>` |
| mise | `~/.mise/installs/` | `mise prune` |
| Deno | `~/.deno/` | `deno cache --reload` (rebuilds on demand) |
| Ruby gems | `~/.gem/specs/` | `gem cleanup` |
| node-gyp | `~/Library/Caches/node-gyp/` | `rm -rf ~/Library/Caches/node-gyp/` |
