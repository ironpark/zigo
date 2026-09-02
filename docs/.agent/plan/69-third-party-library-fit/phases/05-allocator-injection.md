---
depends_on:
- "69-third-party-library-fit#0"
perf_phase: false
status: planned
---
> DONE-WHEN: fixture가 Allocator 없는 C/Go 시그니처로 생성되고 shim이 지정 allocator를 넘긴다.
> NEXT: none

# Allocator/Io 주입

## Planned Work

- `walk.zig`: `.allocator`, `.io` 옵션 파싱. `std.mem.Allocator`/`std.Io` 파라미터를 주입 파라미터로 표시(타입 동일성으로 판별). `semantic.zig`에 주입 정보 기록·직렬화(`injected`). 설정 없이 만나면 `ZIGO022`.
- `emit.zig writeTargetCall`: 주입 식 출력. C/Go 시그니처는 `abi.AbiFn.params`에서 나오므로 자동 제외되는지 확인.
- `abi_diff`: 주입 파라미터 추가·제거는 breaking(시그니처).
- fixture: `fn open(alloc: Allocator, name: []const u8) !*T` 형태. 문서 `bindings.md` 옵션 절.

## Done When

- fixture가 Allocator 없는 C/Go 시그니처로 생성되고 shim이 지정 allocator를 넘긴다.
