---
completed_at: "2026-08-30T09:24:13Z"
description: Audit Zig test discovery and direct coverage of generator, reflection, ABI, build graph, failure atomicity, ownership, and target-specific behavior.
plan_status: done
registered_at: "2026-08-30T09:20:32Z"
---
> NEXT: Zig test discovery와 production 계약별 검증 공백을 감사한다. ([Phase 0](phases/00-inventory-and-prioritized-gap-assessment.md))

# Phases

- [x] [Phase 00: Inventory and prioritized gap assessment](phases/00-inventory-and-prioritized-gap-assessment.md)

# Shared Verification

- `zig build test --summary all`
- `zig build check --summary all`
- test declaration/file inventory와 build dependency graph 대조
- `zig fmt --check .` 및 `git diff --check`

# Decisions That Constrain Ordering

실제 discovery를 먼저 확정한 뒤 간접 통합 근거를 대조해야 test 0개 파일을 잘못 미검증으로
분류하지 않는다. 마지막에 위험도와 구현 비용으로 보강 순서를 정한다.

# Next Implementation Target

Zig test discovery와 production 계약별 검증 공백을 감사한다.
