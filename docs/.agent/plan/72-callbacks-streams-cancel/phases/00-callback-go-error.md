---
perf_phase: false
status: planned
---
> DONE-WHEN: fixture·예제 테스트 통과, 기존 골든 불변.
> NEXT: none

# callback의 Go error 표면화

## Planned Work

- `param_meta.<cb>.go_error`, semantic.json 필드, 검증(Zig 반환 i32 필수). 트램폴린·dispatcher의 `-5`와 state 저장, 공개 래퍼의 `CallbackError`. retained callback의 지연 반환.
- 04-callback 예제에 사용과 Go 테스트(cgo·purego). 문서.

## Done When

- fixture·예제 테스트 통과, 기존 골든 불변.
