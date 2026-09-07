---
completed_at: "2026-09-07T16:15:35Z"
perf_phase: false
status: done
---
> DONE-WHEN: Checks pass, version and tag are pushed, GitHub release is published.
> NEXT: none

# Initial Work

## Planned Work

- Run release.sh 0.18.0 --push, verify checks and published GitHub release, and record completion.

## Done When

- Checks pass, version and tag are pushed, GitHub release is published.

## Release result

- scripts/release.sh 0.18.0 --push passed formatting, full tests (320 steps / 766 tests), all example cgo/purego generated checks and staticcheck U1000.
- Release commit and remote tag: 83e2b7dfb8fcb5a07c01f81a7f6a24710f1c2010. Manifest, changelog and installation references updated.
- GitHub Release workflow 34142150468 completed successfully.
- Published https://github.com/ironpark/zigo/releases/tag/0.18.0 as a non-draft, non-prerelease release. Remote tag matches local tag.
