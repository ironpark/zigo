---
completed_at: "2026-09-02T19:36:00Z"
depends_on:
- "83-go-sub-packages#0"
- "83-go-sub-packages#1"
perf_phase: false
status: done
---
> DONE-WHEN: 골든 통과, 순환 진단 스냅샷, 커밋.
> NEXT: none

# 패키지별 emit과 순환 진단

## Planned Work

- 패키지별 파일 생성, 패키지 간 타입 참조 한정과 import 계산, 순환 진단, ZIGO024 패키지 단위화, `build.zig` 출력 디렉터리·stale 정리·doc, abi_diff.
- cgo·purego 골든(두 패키지, 교차 참조).

## Done When

- 골든 통과, 순환 진단 스냅샷, 커밋.
