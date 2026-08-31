---
completed_at: "2026-08-31T11:57:56Z"
perf_phase: false
status: done
---
> DONE-WHEN: 생성된 Go의 에러 판별이 하나의 규칙으로 설명된다.
> NEXT: none

# One error discrimination rule

## Planned Work

- `Error`, `HandleError`, `ErrInvalidHandle`/`ErrNativePanic`, `LibraryError`의 판별 방식을
  하나의 규칙으로 정리한다.
- panic하는 편의 접근자를 유지할지 결정한다. 유지하면 근거를, 제거하면 마이그레이션을 남긴다.
- `errors.Is` 대상이 무엇인지 문서에 한 표로 정리한다.

## Done When

- 생성된 Go의 에러 판별이 하나의 규칙으로 설명된다.
- 예제 테스트가 새 규칙으로 갱신되고 통과한다.
