---
completed_at: "2026-09-08T01:13:32Z"
description: Match wrappers re-exported through import bindings, widen the receiver witness, and tell same-named alias targets apart by file
plan_status: done
registered_at: "2026-09-08T01:06:36Z"
---
> NEXT: `names.zig`의 세 지점을 고치고 회귀 테스트를 붙인다. ([Phase 0](phases/00-fix.md))

# Phases

- [x] [Phase 00: Fix and regression tests](phases/00-fix.md)
- [x] [Phase 01: Release 0.19.2](phases/01-release.md)

# Shared Verification

- `zig fmt --check`와 `zig build test`.
- 예제 13개의 `go-check`(purego 포함) 뒤 `git status --short examples`가 비어 있을 것.
- 각 수정을 하나씩 되돌려 대응 테스트가 실패하는지 확인(빈 테스트 방지).
- gostty에서: 생성물을 0.18.0 커밋과 diff, `make verify`·`doctor`, `go build`, `go vet`,
  `go test -count=1`, `go test -race`, `examples/hypercat` 빌드.

# Decisions That Constrain Ordering

수정과 테스트가 먼저다. 릴리즈는 gostty로 검증이 끝난 뒤에만 한다 — 태그는 되돌릴 수 없고,
이번 회귀 자체가 태그된 뒤에 발견된 것이다.

# Next Implementation Target

`names.zig`의 세 지점을 고치고 회귀 테스트를 붙인다.
