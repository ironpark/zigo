---
completed_at: "2026-09-02T08:02:11Z"
depends_on:
- "69-third-party-library-fit#5"
perf_phase: false
status: done
---
> DONE-WHEN: fixture 골든 통과, gostty facade 없이 `Terminal` 생성·해제 Go 테스트 통과 보고.
> NEXT: none

# 값 반환 `init`을 caller-owned pointer로

## Planned Work

- `walk.zig`: `.allocator`가 있을 때 값 반환 `init`(`T`/`!T`)을 생성자로 인정, 짝 `deinit`과 pairing.
- `emit.zig`: shim이 `alloc.create` + `init` + 실패 시 `destroy`, `deinit` 래퍼가 `deinit` + `destroy`.
- fixture: `Terminal.init(std.Io, Allocator, Options) !Terminal` 모양(Options는 extern struct 또는 스칼라로 단순화). gostty에서 `src/root.zig`의 D 부분을 제거하고 확인(커밋 금지).
- 문서와 `CHANGELOG.md`.

## Done When

- fixture 골든 통과, gostty facade 없이 `Terminal` 생성·해제 Go 테스트 통과 보고.
