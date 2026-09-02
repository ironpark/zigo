---
completed_at: "2026-09-02T04:42:35Z"
depends_on:
- "64-out-slice-written#0"
perf_phase: false
status: done
---
> DONE-WHEN: shim 골든에 `output_written.* = result`(성공)와 오류 경로 `0`이 있고, `.all` fixture는 `= output_len`을 유지한다.
> NEXT: none

# shim의 `written` 기록과 공개 계층의 되돌리기 규칙

## Planned Work

- `src/gen/emit.zig` `writeSliceWrittenAssignments`: `.return`이면 `{p}_written.* = result`, `.all`이면 기존 `len`. 오류 유니온의 오류 경로에서는 out 파라미터마다 `0`을 기록.
- plain 반환 함수도 `const result = …;` 뒤에 `written` 대입 후 `return result`가 나가도록 shim 렌더링을 정리한다.
- `isCountReturn` 휴리스틱 제거. `writePublicValueStructSliceCopyBacks`는 raw가 돌려준 `written`(`int(outputWritten)` 등 raw 반환값)만 사용한다. raw cgo·purego 함수가 `written`을 공개 계층에 돌려주는 경로가 없다면 이 단계에서 만든다.
- `tests/generator_cases/value_struct` fixture의 `fillPoints`에 `.written = .return` 부여, 골든 갱신. `.all` 케이스도 하나 남긴다.

## Done When

- shim 골든에 `output_written.* = result`(성공)와 오류 경로 `0`이 있고, `.all` fixture는 `= output_len`을 유지한다.
- 공개 골든이 `written` 만큼만 되돌리고 `isCountReturn` 참조가 소스에 없다.
- `zig build test` 통과.
