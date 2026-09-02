---
description: N단계 바인딩 경로, 비 2의거듭제곱 정수 폭 승격, 위치 정보가 있는 생성기 진단
plan_status: in-progress
registered_at: "2026-09-02T06:00:06Z"
---
> NEXT: `supported()`를 `findIssue`의 `ZIGO018`/`ZIGO019` 진단으로 흡수하고 walk.zig의 comptime 메시지에 경로·파라미터를 넣는다. ([Phase 0](phases/00-located-diagnostics.md))

# Phases

- [x] [Phase 00: 지원되지 않는 타입을 위치 있는 진단으로](phases/00-located-diagnostics.md)
- [x] [Phase 01: 비 2의거듭제곱 정수 폭 승격](phases/01-int-width-promotion.md)
- [ ] [Phase 02: N단계 바인딩 경로](phases/02-nested-paths.md)

# Shared Verification

- `zig build test --summary all`, `zig fmt --check build.zig src tests examples`(CI가 검사한다).
- 예제 루프(`docs/development.md`) + purego 4개(04, 07, 08은 `zig build purego-go`/`purego-go-check`, 10은 `zig build go -Dpurego=true`).
- 골든 갱신은 실패 출력의 actual 경로를 `zig build snapshot -- <expected> <actual> --update-snapshots`에 넘긴다.
- gostty: `cd ../gostty && zig build go && zig build && (cd go && go test ./...)`.

# Decisions That Constrain Ordering

0 → 1, 0 → 2. 1과 2는 독립이라 병행 가능. 각 phase 별도 커밋. 진단(0)을 먼저 두는 이유는 1·2의 새 거부 사유가 처음부터 위치 있는 메시지로 나가게 하기 위해서다.

# Next Implementation Target

`supported()`를 `findIssue`의 `ZIGO018`/`ZIGO019` 진단으로 흡수하고 walk.zig의 comptime 메시지에 경로·파라미터를 넣는다.
