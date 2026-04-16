# Apple System Directories

Directories under ~/Library/Application Support/ to always skip during orphan detection. These are Apple system directories, not application data.

| Pattern | Notes |
|---------|-------|
| `com.apple.*` | All Apple system services |
| `CallHistory*` | Call history data |
| `CloudDocs` | iCloud Drive metadata |
| `iCloud*` | iCloud sync services |
| `Spotlight` | Search index metadata |
| `Music` | Apple Music data |
| `Claude` (exact match) | Claude Code data (never touch). Exact-match only — do not fuzzy-match; a third-party app legitimately named "Claude-Foo" should still be evaluated as a normal orphan candidate. |
| `Knowledge*` | Siri/Knowledge services |
| `StatusKit*` | Focus/Status services |
| `CrashReporter` | System crash reporter |
| `SyncServices` | System sync services |

Also always skip anything under ~/.claude/ — this is Claude's own configuration.
