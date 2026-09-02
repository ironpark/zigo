---
perf_phase: false
status: planned
---
> DONE-WHEN: `fn freeString(gpa: Allocator, str: []const u8) void`에 `.params = .{"str"}`·`.release` 지정이 cgo·purego 예제에서 통과.
> NEXT: none

# 주입 파라미터 arity와 release 매칭

## Planned Work

- `concreteParamCount/Index`가 주입 파라미터(`injectionFor != null`)를 건너뛰도록 하고, `.params` 길이 불일치를 `ZIGO027` 진단으로 낸다.
- `validate.zig` release 매칭에서 `injected != null` 파라미터를 제외한다. `emit.zig`가 release 함수 호출 시 주입 인자를 채운다(cgo·purego 공통 shim).
- `src/root.zig`의 중복 allocator 상수를 제거하고 release가 주입을 쓰게 바꾼다.
- 테스트: 짧은 `.params` 통과, 길이 불일치 진단 스냅샷, allocator 주입 release 골든.

## Done When

- `fn freeString(gpa: Allocator, str: []const u8) void`에 `.params = .{"str"}`·`.release` 지정이 cgo·purego 예제에서 통과.
- `zig build test`, 전 예제 루프 녹색, 커밋.
