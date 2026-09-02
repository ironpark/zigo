---
completed_at: "2026-09-02T08:38:21Z"
depends_on:
- "70-io-stream-params#0"
perf_phase: false
status: done
---
> DONE-WHEN: 골든 shim이 컴파일되고 `drain`/`stream` 계약(버퍼 선소비, splat, EndOfStream)을 shim 단위 테스트(Zig test)로 검증한다.
> NEXT: none

# shim 어댑터와 lowering

## Planned Work

- `lower.zig`: 스트림 파라미터를 고정 시그니처 callback으로 lowering(cgo userdata-only, purego fn pointer + userdata). 헤더 typedef(purego)와 C 선언.
- `emit.zig` shim: 어댑터 타입 2종을 파일당 한 번 출력(스트림 파라미터가 있을 때만), 함수별로 버퍼·어댑터 생성, 호출 뒤 `flush`, 실패 매핑, `-3` 이후 재호출 금지.
- 골든 `tests/generator_cases/io_stream`(cgo·purego 둘 다 생성되는 케이스 구성 방식은 기존 케이스 참조). shim이 `zig build`로 컴파일되는지 골든 아티팩트 검사에 포함.

## Notes

- 어댑터는 `src/gen/stream_adapter.zig`라는 진짜 Zig 파일에 두고 `emit.zig`가 마커 사이 구간을 `@embedFile`로 심는다. 문자열 상수로만 두면 `drain`/`stream` 계약을 컴파일해 볼 방법이 없다. 같은 텍스트가 테스트되고 심어지므로 둘이 어긋날 수 없다.
- **골든 `tests/generator_cases/io_stream`은 phase 02로 옮겼다.** 케이스 러너는 shim·헤더·cgo raw·public Go를 한 번에 렌더하고 하나라도 실패하면 아무 파일도 쓰지 않으므로, Go 레이어가 없는 상태에서는 골든을 만들 수 없다. 이 phase의 shim 검증은 (1) `stream_adapter.zig`의 계약 테스트 6종(버퍼 선소비, splat 반복, drain 반환값, 버퍼 대비 크로싱 상한, 실패 후 재진입 금지, EOF)과 (2) `emit.zig`의 렌더 단정(트램폴린 extern 2종, 어댑터 1회 출력, 스택/힙 버퍼 분기, `flush` defer, 대상 호출 인자, C 헤더 시그니처)으로 했다. 골든 `ast-check`는 phase 02가 붙인다.

## Done When

- 골든 shim이 컴파일되고 `drain`/`stream` 계약(버퍼 선소비, splat, EndOfStream)을 shim 단위 테스트(Zig test)로 검증한다.
