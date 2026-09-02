---
completed_at: "2026-09-02T06:23:04Z"
depends_on:
- "67-consume-ghostty-vt#0"
perf_phase: false
status: done
---
> DONE-WHEN: `u21` fixture 골든: 헤더 `uint32_t`, Go `uint32`, shim 범위검사·`@intCast`, `semantic.json` `bits: 21`.
> NEXT: none

# 비 2의거듭제곱 정수 폭 승격

## Planned Work

- `validate.zig integerSupported`: `1 <= bits <= 64`. 위치별 예외(extern struct 필드, 슬라이스 원소, callback 시그니처)는 `ZIGO018`로 이유를 담아 거부 유지 — 각 위치를 fixture로 고정.
- `lower.zig:680-685`: ABI 폭 승격, 원 폭 보존(`abi.AbiScalar`에 필드 추가 또는 별도 기록).
- `emit.zig`: 진입 범위검사 + `@intCast`(`writeTargetCall`), 반환 `@intCast`(`writeZigReturnConversion`), out 파라미터·에러 유니온 payload 경로. 헤더·Go 타입은 승격 폭. shim 골든에 범위검사가 보이도록 fixture(`u21` 파라미터와 `u21` 반환, `i24`도 하나).
- Go 테스트: 범위 밖 값이 `NativePanicError`로 돌아오고 핸들이 poison되지 않는(핸들 없는 함수) 또는 poison되는(메서드) 동작을 예제 하나에서 확인. `docs/bindings.md` 스칼라 표와 `limitations.md` 갱신.

## Done When

- `u21` fixture 골든: 헤더 `uint32_t`, Go `uint32`, shim 범위검사·`@intCast`, `semantic.json` `bits: 21`.
- 범위 밖 값의 Go 테스트 통과. `zig build test`와 예제 전부 통과, 기존 골든 불변.
