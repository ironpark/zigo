---
perf_phase: false
status: in-progress
---
> DONE-WHEN: reflect 테스트에서 getter/setter `ext.get("TEST")`가 읽히고 `zig build test` 통과, 커밋.
> NEXT: none

# HandleField.ext

## Planned Work

- declare.HandleField에 `ext`와 `extend(P, P.FunctionOptions)` 추가, normalize에서 중복 플러그인 검사.
- walk.appendFieldAccessors가 getter/setter에 ext 전달.
- 테스트(walk.zig), docs/bindings-handles.md·plugins.md 갱신.

## Done When

- reflect 테스트에서 getter/setter `ext.get("TEST")`가 읽히고 `zig build test` 통과, 커밋.
