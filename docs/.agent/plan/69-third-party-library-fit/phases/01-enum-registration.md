---
depends_on:
- "69-third-party-library-fit#0"
perf_phase: false
status: planned
---
> DONE-WHEN: 위 fixture 골든과 예제 통과, 문서 갱신.
> NEXT: none

# enum을 `.types`에 등록

## Planned Work

- `walk.zig`: `.repr = .enumeration` arm(`.name` 선택, enum이 아니면 `@compileError`). 암묵 발견 시 `zig_path`로 등록 항목 우선 조회.
- fixture: 익명 enum을 `.name = "CursorStyle"`로 등록 → Go `CursorStyle`, C `zg_cursor_style`, semantic.json 이름. 등록 없이 같은 타입 → phase 0의 `ZIGO021`.
- 예제 하나(09-type-relations)에 등록 enum 사용. `docs/bindings.md`의 "등록 enum" 표현을 실제 등록 수단과 맞춘다.

## Done When

- 위 fixture 골든과 예제 통과, 문서 갱신.
