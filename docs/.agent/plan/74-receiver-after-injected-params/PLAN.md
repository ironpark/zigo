---
completed_at: "2026-09-02T13:27:12Z"
description: 주입 파라미터(Allocator, Io) 뒤에 오는 handle 파라미터도 receiver/.destroys 대상으로 인식
plan_status: done
registered_at: "2026-09-02T13:21:45Z"
---
> NEXT: 주입 파라미터 뒤의 handle을 receiver로 인식한다. ([Phase 0](phases/00-receiver-skip-injected.md))

# Phases

- [x] [Phase 00: 주입 파라미터 뒤의 receiver](phases/00-receiver-skip-injected.md)

# Shared Verification

`zig build test`, `zig fmt --check`, 전 예제 cgo+purego 루프.

# Decisions That Constrain Ordering

단일 phase.

# Next Implementation Target

주입 파라미터 뒤의 handle을 receiver로 인식한다.
