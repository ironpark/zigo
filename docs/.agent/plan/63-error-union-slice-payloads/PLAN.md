---
completed_at: "2026-09-01T23:48:14Z"
depends_on:
- slice-ownership-and-struct-elements
description: Lower error-union slice payloads (![]T) to ptr+len out parameters on both backends and integrate caller-owned release
plan_status: done
registered_at: "2026-09-01T23:32:57Z"
---
> NEXT: Lower `![]T` payloads to `out_result_ptr`/`out_result_len` and emit the success-only write on both backends. ([Phase 0](phases/00-error-union-slice-lowering.md))

# Phases

- [x] [Phase 00: Lower and emit error-union slice payloads](phases/00-error-union-slice-lowering.md)
- [x] [Phase 01: Caller-owned release for error-union slice payloads](phases/01-error-union-slice-release.md)

# Shared Verification

- `zig build test --summary all` at the root after each phase (clear
  `.zig-cache/h` if generator-case inputs do not invalidate).
- `examples/07-event-queue`: `zig build test go-check abi-check --summary all`,
  `zig build go`, `(cd go && go test -count=1 ./...)`, `zig build purego-go
  purego-go-verify --summary all`, `(cd go-purego && CGO_ENABLED=0 go test
  ./...)`; `git status --short` clean after commit.

# Decisions That Constrain Ordering

Phase 0 then phase 1; phase 1 reuses the release plumbing from plan 61 phase 4
and only gates it on the error code.

# Next Implementation Target

Lower `![]T` payloads to `out_result_ptr`/`out_result_len` and emit the success-only write on both backends.
