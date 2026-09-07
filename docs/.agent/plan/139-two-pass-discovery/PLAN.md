---
description: discovery를 항목 주도 패스와 런타임 집합 기반 탐색 패스로 나눠 comptime 교차 조회를 없앤다
plan_status: in-progress
registered_at: "2026-09-07T04:06:31Z"
---
> NEXT: walk 두 패스. ([Phase 0](phases/00-walk-two-pass.md))

# Phases

- [x] [Phase 00: Two-pass discovery in walk](phases/00-walk-two-pass.md)
- [ ] [Phase 01: Runtime sets in coverage and example regeneration](phases/01-coverage-and-examples.md)

# Shared Verification

`zig build test --summary all`, `scripts/release.sh`의 예제 루프와 동일한 go-check.

# Decisions That Constrain Ordering

0 → 1.

# Next Implementation Target

walk 두 패스.
