---
completed_at: "2026-09-12T18:18:22Z"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test`가 통과한다.
> NEXT: none

# kind 목록 계약

## Planned Work

- `src/features.zig`의 `FunctionOptions`를 `kind: ?ir.Implements = null`과
  `kinds: []const ir.Implements = &.{}`로 바꿉니다.
- `src/author.zig`의 `use`가 built-in 페이로드에 목록을 담도록 고치고, 둘 다 주거나
  아무것도 주지 않은 선언을 `@compileError`로 거절합니다.
- `src/declare.zig`의 built-in union 페이로드와 `Function.implements`를 목록으로 바꾸고,
  `src/normalize.zig`가 그대로 옮기게 합니다.
- `src/reflect/walk.zig`가 목록을 `FnGo.implements`에 넣도록 고치고, 그 테스트를 배열
  spelling으로 갱신합니다.
- `src/gen/ir/semantic.zig`의 `FnGo.implements`를 `?[]const Implements`로 바꾸고
  `goImplements`/`setGoImplements`를 목록으로 맞춥니다. 비어 있으면 `null`로 compact해
  `semantic.json`에 나타나지 않게 합니다.
- `migrate`에 규칙을 더합니다: `go.implements`가 문자열이면 한 원소 배열로 감쌉니다.
  round-trip 테스트에 옛 문자열 문서 하나를 넣어 읽히는 것을 확인합니다.
- 같은 kind가 두 번 나열된 선언을 `ZIGO058`로 거절합니다.

## Done When

- `zig build test`가 통과한다.
- `.kind` 하나를 쓰는 선언의 semantic과 생성 출력이 바뀌지 않는다.
- 문자열로 적힌 `implements`를 가진 `semantic.json`이 그대로 읽힌다.
- 같은 kind를 두 번 나열하면 `ZIGO058`이 난다.
