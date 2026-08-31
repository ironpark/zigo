---
completed_at: "2026-08-31T10:37:06Z"
description: Compile the generator case goldens so a non-compiling emitted panic.c or shim cannot be pinned
plan_status: done
registered_at: "2026-08-31T10:35:43Z"
---
> NEXT: 골든 컴파일 검사 배선. ([Phase 0](phases/00-compile-goldens.md))

# Phases

- [x] [Phase 00: Compile the goldens](phases/00-compile-goldens.md)

# Shared Verification

`zig build test` 실행. 이어서 골든 하나의 include를 임시로 지우고 실패를 확인한 뒤 되돌린다.

# Decisions That Constrain Ordering

단일 단계.

# Next Implementation Target

골든 컴파일 검사 배선.
