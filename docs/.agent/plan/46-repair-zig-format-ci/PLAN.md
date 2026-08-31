---
description: CI에서 발견된 src/gen/emit.zig 포맷 실패를 수정하고 포맷·테스트를 검증한다.
plan_status: in-progress
registered_at: "2026-08-31T17:54:35Z"
---
> NEXT: CI가 지목한 Zig 파일을 정규 포맷으로 갱신하고 전체 검증을 실행한다. ([Phase 0](phases/00-repair-zig-formatting.md))

# Phases

- [ ] [Phase 00: Repair Zig formatting](phases/00-repair-zig-formatting.md)

# Shared Verification

- `zig fmt --check build.zig src tests examples`
- `zig build test --summary all`

# Decisions That Constrain Ordering

단일 phase에서 포맷과 검증을 수행한다.

# Next Implementation Target

CI가 지목한 Zig 파일을 정규 포맷으로 갱신하고 전체 검증을 실행한다.
