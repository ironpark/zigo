---
completed_at: "2026-09-08T00:14:37Z"
perf_phase: false
status: done
---
> DONE-WHEN: origin에 0.19.0 태그가 있고 워크플로가 시작됨.
> NEXT: none

# Release

## Planned Work

- `scripts/release.sh 0.19.0` 실행 후 브랜치와 태그 푸시.

## Done When

- origin에 0.19.0 태그가 있고 워크플로가 시작됨.

## Release result

- scripts/release.sh 0.19.0 passed formatting, full tests, all example cgo/purego generated checks and staticcheck U1000.
- Release commit and remote tag: ff534ea6. Manifest, changelog and installation references updated.
- GitHub Release workflow 34172515887 completed successfully.
- Published https://github.com/ironpark/zigo/releases/tag/0.19.0 as a non-draft, non-prerelease release.
