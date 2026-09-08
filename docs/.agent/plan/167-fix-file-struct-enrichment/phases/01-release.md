---
depends_on:
- "167-fix-file-struct-enrichment#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: GitHub 릴리스 0.19.1 공개.
> NEXT: none

# Release 0.19.1

## Planned Work

- `scripts/release.sh 0.19.1` 후 푸시, 워크플로 확인.

## Done When

- GitHub 릴리스 0.19.1 공개.

## Release result

- scripts/release.sh 0.19.1 passed formatting, full tests, all example cgo/purego generated checks and staticcheck U1000.
- Release commit and remote tag: 1d8e7e49. GitHub Release workflow 34173969496 completed successfully.
- Published https://github.com/ironpark/zigo/releases/tag/0.19.1 as a non-draft release.
