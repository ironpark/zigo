---
perf_phase: false
status: planned
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

## Done When

- fixture 6종(writer, reader, 반환 위치, 필드 위치, callback 위치, retained)이 기대대로 통과·거부된다.
