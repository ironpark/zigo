---
perf_phase: false
status: planned
---
> DONE-WHEN: 취소 테스트 통과, 취소 없는 함수의 골든 불변.
> NEXT: none

# 취소 규약

## Planned Work

- 설계 결정(Go 소유 플래그 vs 폴링 함수 포인터) 기록. `.cancel` 메타, 검증, lowering, shim, Go `ctx` 래퍼와 감시 goroutine, `context.Canceled` 매핑.
- 예제(08-telemetry-hub 또는 11)에 긴 호출과 취소 테스트. 문서.

## Done When

- 취소 테스트 통과, 취소 없는 함수의 골든 불변.
