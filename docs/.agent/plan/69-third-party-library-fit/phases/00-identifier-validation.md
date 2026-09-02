---
completed_at: "2026-09-02T07:21:29Z"
perf_phase: false
status: done
---
> DONE-WHEN: 두 fixture가 `ZIGO021`로 거부되고 메시지에 Zig 타입 경로가 있다.
> NEXT: none

# 유도 Go 식별자 검증

## Planned Work

- `validate.zig`: 타입·enum tag·함수·필드·variant·`.name`의 모든 Go 이름을 `naming.isGoIdentifier`와 예약어 목록으로 검사, `ZIGO021`에 Zig 경로와 `.name` 힌트.
- fixture: `@typeName`이 `...[0..4])`로 끝나는 enum(`std.meta`/`@Type`으로 만든 익명 enum)을 시그니처에 둔 semantic.json → `ZIGO021`. 예약어 이름 fixture.
- CLI 계약 테스트: 진단이 gofmt 전에 나온다.

## Done When

- 두 fixture가 `ZIGO021`로 거부되고 메시지에 Zig 타입 경로가 있다.
