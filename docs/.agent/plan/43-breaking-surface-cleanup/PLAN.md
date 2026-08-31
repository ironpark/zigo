---
description: Collapse duplicated axes in the build options, declaration DSL and generated Go surface
plan_status: in-progress
registered_at: "2026-08-31T10:38:14Z"
---
> NEXT: 소비되지 않는 layout 산출물 제거부터 시작한다. ([Phase 0](phases/00-drop-layout-artifact.md))

# Phases

- [x] [Phase 00: Drop the unused layout artifact](phases/00-drop-layout-artifact.md)
- [ ] [Phase 01: Collapse the build option axes](phases/01-collapse-option-axes.md)
- [ ] [Phase 02: One way to name a declaration](phases/02-unified-declaration-paths.md)
- [ ] [Phase 03: Separate type kind from access strategy](phases/03-split-repr-axis.md)
- [ ] [Phase 04: One error discrimination rule](phases/04-unify-go-errors.md)

# Shared Verification

phase마다 `zig build test`, 그리고 영향받는 예제에서 `zig build go go-check abi-check`와
cgo·purego `go test`를 실행한다. 옵션과 DSL 변경은 예제 10종 전부를 갱신해야 하므로
`examples/` 전체를 회귀 대상으로 본다.

# Decisions That Constrain Ordering

0과 1은 독립이다. 2 → 3은 순서가 있다. 4는 독립이며 마지막에 두어 앞선 변경의 영향을 받는다.
표면을 여러 번 깨지 않도록 한 릴리스로 묶어 내보내는 것을 권한다.

# Next Implementation Target

소비되지 않는 layout 산출물 제거부터 시작한다.
