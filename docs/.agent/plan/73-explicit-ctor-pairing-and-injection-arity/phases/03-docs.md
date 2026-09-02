---
completed_at: "2026-09-02T13:04:46Z"
depends_on:
- "73-explicit-ctor-pairing-and-injection-arity#0"
- "73-explicit-ctor-pairing-and-injection-arity#2"
perf_phase: false
status: done
---
> DONE-WHEN: 문서에 남은 옛 안내 없음(`grep`으로 확인), `zig build test` 녹색, 커밋.
> NEXT: none

# 문서와 CHANGELOG

## Planned Work

- `docs/bindings.md`의 "이름 규칙 벗어나면 `.returns = .caller`" 안내를 `.constructs`/`.destroys`로 교체, `.params`가 주입 파라미터를 제외한다는 규칙과 `.release` 주입 명시.
- `docs/limitations.md`, `docs/generated-code.md`, 진단 코드 목록에 `ZIGO027`/`ZIGO028` 추가.
- `CHANGELOG.md` Unreleased에 Added(메타)·Fixed(호출 경로, arity) 기재.

## Done When

- 문서에 남은 옛 안내 없음(`grep`으로 확인), `zig build test` 녹색, 커밋.
