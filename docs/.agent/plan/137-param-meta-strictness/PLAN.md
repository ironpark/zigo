---
description: param_meta 고아 키를 거부하고 C 예약어 파라미터 이름을 거부한다
plan_status: in-progress
registered_at: "2026-09-07T02:46:55Z"
---
> NEXT: param_meta 고아 키 거부. ([Phase 0](phases/00-orphan-param-meta.md))

# Phases

- [x] [Phase 00: Reject orphaned param_meta keys](phases/00-orphan-param-meta.md)
- [x] [Phase 01: Reject C keyword parameter names](phases/01-c-keyword-params.md)
- [ ] [Phase 02: Index bound function paths once](phases/02-index-bound-function-paths-once.md)

# Shared Verification

`zig build test` 전체 통과.

# Decisions That Constrain Ordering

두 phase는 독립적이다.

# Next Implementation Target

param_meta 고아 키 거부.
