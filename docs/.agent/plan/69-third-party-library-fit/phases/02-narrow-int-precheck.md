---
perf_phase: false
status: planned
---
> DONE-WHEN: 범위 밖 값이 cgo 호출 없이 `ErrOutOfRange`로 돌아오는 테스트 통과.
> NEXT: none

# 승격 정수의 Go 사전검사

## Planned Work

- `emit.zig`: 승격 파라미터가 있는 함수를 checked 시그니처로 승격, cgo 호출 전 범위검사, `RangeError`/`ErrOutOfRange` 타입을 errors 파일에 생성(승격 파라미터가 있을 때만).
- shim 가드 유지. `docs/limitations.md`의 승격 정수 절을 Go 사전검사 기준으로 고친다.
- 02-errors 예제의 `codepointWidth` Go 테스트를 `ErrOutOfRange`와 `LastErrorMessage() == ""` 기준으로 갱신. `narrow_int` 골든 갱신.

## Done When

- 범위 밖 값이 cgo 호출 없이 `ErrOutOfRange`로 돌아오는 테스트 통과.
