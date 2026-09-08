---
description: Publish 0.21.0 with the plugin contract 2.0 rewrite and the plugin_config migration
plan_status: in-progress
registered_at: "2026-09-08T06:38:56Z"
---
> NEXT: Write the changelog section and run the release checks for 0.21.0. ([Phase 0](phases/00-release.md))

# Phases

- [ ] [Phase 00: Release 0.21.0](phases/00-release.md)

# Shared Verification

`scripts/release.sh 0.21.0` completes: `zig fmt --check`, `zig build test`,
every example `go-check`, staticcheck over the example Go modules, then the
bump commit and the tag. After pushing, the Release workflow run succeeds and
`gh release view 0.21.0` shows the changelog section.

# Decisions That Constrain Ordering

Single phase; the checks must pass before the tag is pushed.

# Next Implementation Target

Write the changelog section and run the release checks for 0.21.0.
