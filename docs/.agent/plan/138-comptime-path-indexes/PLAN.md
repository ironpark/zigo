---
description: reflect의 comptime 선형 조회(exclude, discovery 항목 매칭)를 한 번 만든 색인으로 대체
plan_status: in-progress
registered_at: "2026-09-07T02:57:39Z"
---
> NEXT: exclude 색인. ([Phase 0](phases/00-exclude-index.md))

# Phases

- [x] [Phase 00: Index excluded paths](phases/00-exclude-index.md)
- [ ] [Phase 01: Index bound entries by path](phases/01-entry-index.md)

# Shared Verification

`zig build test --summary all`, `examples/07-event-queue`에서 `zig build test go-coverage`.

# Decisions That Constrain Ordering

0 → 1.

# Next Implementation Target

exclude 색인.
