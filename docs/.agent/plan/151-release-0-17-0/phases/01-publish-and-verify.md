---
depends_on:
- "151-release-0-17-0#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: GitHub release 0.17.0 is published and points to the intended commit.
> NEXT: none

# Publish and verify

## Planned Work

- Push main and the release tag to origin.
- Verify the tag target, Release workflow and published GitHub release.

## Done When

- GitHub release 0.17.0 is published and points to the intended commit.

## Release evidence

- `scripts/release.sh 0.17.0` passed all checks: Zig formatting, 756 tests / 282 build steps, all example cgo/purego generated-tree checks, and staticcheck U1000.
- Release commit: 43cd37ecb4c9c0e7d6f3836383ba4dcaac7a95ed. Version metadata, changelog and fetch instructions agree on 0.17.0.
- Pushed main and tag 0.17.0. `git ls-remote` confirms the remote tag resolves to the release commit.
- GitHub Release workflow 34113778932 completed successfully on the release commit.
- https://github.com/ironpark/zigo/releases/tag/0.17.0 is published, neither draft nor prerelease; published_at is 2026-09-07T10:55:12Z.
