---
perf_phase: false
status: in-progress
---
> DONE-WHEN: fixture 6종(writer, reader, 반환 위치, 필드 위치, callback 위치, retained)이 기대대로 통과·거부된다.
> NEXT: none

# 스트림 파라미터 인식과 IR

## Planned Work

- `walk.zig`: `*std.Io.Writer`/`*std.Io.Reader` 인식 → `TypeNode.io_stream`. `param_meta.buffer` 반영.
- `semantic.zig`: 노드, JSON 직렬화·역직렬화, `buffer`.
- `validate.zig`: 위치 제한과 `.retained` 거부, buffer 범위를 새 진단 코드로. 메시지에 `Owner.fn`·파라미터.
- `abi_diff.zig`: kind breaking, buffer compatible 테스트.
- 단위 테스트와 `walk.zig` 골든 JSON.

## Decisions

- 진단 코드는 `ZIGO023` 하나로 통일했다. 스트림의 거부 사유(위치, `.retained`, `buffer` 범위, 비스트림 `buffer`)는 모두 "어댑터가 호출 스택에 산다"는 같은 사실에서 나오므로, 코드를 넷으로 쪼개면 `errors.Is` 수준의 구분을 얻지 못한 채 번호만 늘어난다. 메시지가 각각 다르고 `Owner.fn`과 파라미터 이름을 담는다.
- `buffer`는 `TypeNode.io_stream`이 아니라 `semantic.Parameter.buffer: ?u32`에 둔다. `param_meta` 사이드카가 파라미터 단위 노브이고(`written`/`retention`과 같은 축), `typeEqual`이 방향만 보면 되므로 abi_diff가 단순해진다. 버퍼 변경은 `streamBufferEqual`이 `compatible` 변경으로 보고한다.
- **계획 72 phase 1(`[]byte` 무콜백 Reader 경로) 대비:** 그 fast path는 Go가 콜백 대신 바이트 슬라이스를 그대로 넘기는 것이므로, reader 파라미터의 C 시그니처에 `ptr`+`len` 두 인자가 더 필요하다. 나중에 붙이면 reader를 쓰는 모든 바인딩이 breaking이 된다. 그래서 **이 계획에서 reader의 C 시그니처에 슬라이스 쌍을 미리 넣는다**: cgo `(const uint8_t *r_data, size_t r_data_len, size_t r_userdata)`, purego `(fnptr, const uint8_t *, size_t, uintptr)`. shim은 `r_data != null`이면 `std.Io.Reader.fixed(r_data[0..r_data_len])`을 쓰고 콜백을 한 번도 부르지 않으며, null이면 콜백 어댑터를 쓴다. 지금 Go 쪽은 항상 null/0을 넘긴다 — 즉 ABI 자리는 예약하고 동작은 72에 남긴다. writer에는 대응 변형이 없다(출력 크기를 미리 알 수 없다). 계획 72는 건드리지 않았다.

## Done When

- fixture 6종(writer, reader, 반환 위치, 필드 위치, callback 위치, retained)이 기대대로 통과·거부된다.
