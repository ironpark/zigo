---
depends_on:
- "70-io-stream-params#0"
perf_phase: false
status: planned
---
> DONE-WHEN: 골든 shim이 컴파일되고 `drain`/`stream` 계약(버퍼 선소비, splat, EndOfStream)을 shim 단위 테스트(Zig test)로 검증한다.
> NEXT: none

# shim 어댑터와 lowering

## Planned Work

- `lower.zig`: 스트림 파라미터를 고정 시그니처 callback으로 lowering(cgo userdata-only, purego fn pointer + userdata). 헤더 typedef(purego)와 C 선언.
- `emit.zig` shim: 어댑터 타입 2종을 파일당 한 번 출력(스트림 파라미터가 있을 때만), 함수별로 버퍼·어댑터 생성, 호출 뒤 `flush`, 실패 매핑, `-3` 이후 재호출 금지.
- 골든 `tests/generator_cases/io_stream`(cgo·purego 둘 다 생성되는 케이스 구성 방식은 기존 케이스 참조). shim이 `zig build`로 컴파일되는지 골든 아티팩트 검사에 포함.

## Done When

- 골든 shim이 컴파일되고 `drain`/`stream` 계약(버퍼 선소비, splat, EndOfStream)을 shim 단위 테스트(Zig test)로 검증한다.
