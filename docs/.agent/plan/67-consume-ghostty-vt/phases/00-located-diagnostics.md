---
completed_at: "2026-09-02T06:12:52Z"
perf_phase: false
status: done
---
> DONE-WHEN: `grep -n "return error.Unsupported" src/gen/validate.zig`가 비어 있고, 진단 골든 테스트가 통과한다.
> NEXT: none

# 지원되지 않는 타입을 위치 있는 진단으로

## Planned Work

- `validate.zig`: `supported()` 순회를 `findIssue`로 옮겨 `ZIGO018`(정수·실수 폭), `ZIGO019`(타입)을 낸다. `site.declaration = "Owner.fn"`, message에 파라미터 이름/`return`과 Zig 철자, hint에 대안(정수 폭은 phase 1 전까지 "8/16/32/64로 바꾸라", 이후 자동 승격 안내로 갱신).
- `UnsupportedIrVersion`, `InvalidName`도 진단으로. `semanticDocument`는 `findIssue` 뒤 `error.InvalidSemantic` 하나만.
- `walk.zig` comptime 메시지(`:255-262, 371-420, 393-408, 419, 483, 487`)에 `entry.path`와 파라미터 이름을 넣는다.
- CLI 출력에서 스택 트레이스가 아닌 진단만 보이는지 확인(`src/cli` 또는 `doctor` 경로의 error 처리).
- 테스트: `u21` fixture가 `ZIGO018`과 `Owner.fn`·파라미터 이름을 출력, `f80`·미지원 타입 fixture가 `ZIGO019`. 기존 bare error 기대 테스트 갱신.

## Done When

- `grep -n "return error.Unsupported" src/gen/validate.zig`가 비어 있고, 진단 골든 테스트가 통과한다.
- `docs/limitations.md` 진단 목록에 `ZIGO018`, `ZIGO019` 추가.
