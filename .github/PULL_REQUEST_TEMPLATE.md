## Summary

<!-- What changed and why. One or two sentences. -->

## Type of change

- [ ] Bug fix (a safety rule was wrong, a path was wrong, a phase misbehaved)
- [ ] New cleanup category or heuristic
- [ ] Refactor (no behavior change)
- [ ] Docs / metadata only

## Changes

<!-- Bullet list of what's in the diff. -->

-

## Test plan

<!-- How did you verify this? E.g., "ran `/upkeep audit` on my machine, Phase 4 now asks before touching Saved State". If the change is metadata/docs only, say so. -->

- [ ]

## Safety review (for changes that modify or delete files)

- [ ] The change is gated behind user approval
- [ ] Sizes are reported before removal
- [ ] Protected directories (`~/.claude/`, `com.apple.*`, installed-app data, keychains, preferences) are still protected
- [ ] No new `sudo` usage
- [ ] N/A — this change doesn't touch removal logic

## Related issues

<!-- Closes #123, or leave blank -->
