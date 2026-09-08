---
completed_at: "2026-09-08T01:13:32Z"
depends_on:
- "168-fix-alias-owner-enrichment#0"
perf_phase: false
status: done
---
> DONE-WHEN: 태그 `0.19.2`가 origin에 있고 릴리즈 워크플로가 노트를 게시했다.
> NEXT: none

# Release 0.19.2

## Planned Work

- `CHANGELOG.md`의 `## [Unreleased]`에 세 항목을 적는다.
- `scripts/release.sh 0.19.2 --push`로 검사·버전업 커밋·태그·푸시를 실행한다.
- gostty의 `zig/build.zig.zon`을 0.19.2 태그와 해시로 고정하고 재생성한다.

## Done When

- 태그 `0.19.2`가 origin에 있고 릴리즈 워크플로가 노트를 게시했다.
- gostty가 0.19.2를 핀으로 잡고 `make check`·`verify`·테스트를 통과한다.
