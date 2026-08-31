---
completed_at: "2026-08-31T18:00:17Z"
description: Linux cgo에서 event-queue layout helper의 offsetof 심볼 링크 실패를 수정하고 생성·테스트 경로를 검증한다.
plan_status: done
registered_at: "2026-08-31T17:58:48Z"
---
> NEXT: Linux cgo가 외부 symbol 없이 offset을 읽도록 layout helper를 수정한다. ([Phase 0](phases/00-use-cgo-compile-time-offsets.md))

# Phases

- [x] [Phase 00: Use cgo compile-time offsets](phases/00-use-cgo-compile-time-offsets.md)

# Shared Verification

- `gofmt -w` 후 `go test ./...` in `examples/07-event-queue/go`
- `zig build go-check` in `examples/07-event-queue`
- `zig fmt --check build.zig src tests examples`
- `zig build test --summary all`

# Decisions That Constrain Ordering

단일 phase에서 helper 수정과 회귀 검증을 수행한다.

# Next Implementation Target

Linux cgo가 외부 symbol 없이 offset을 읽도록 layout helper를 수정한다.
