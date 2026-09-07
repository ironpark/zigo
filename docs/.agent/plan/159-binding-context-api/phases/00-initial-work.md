---
completed_at: "2026-09-07T14:38:18Z"
perf_phase: false
status: done
---
> DONE-WHEN: All checks pass and source, examples, docs and plan are committed.
> NEXT: none

# Initial Work

## Planned Work

- Implement Context, migrate four examples, document the API, and verify regressions and generation.

## Done When

- All checks pass and source, examples, docs and plan are committed.

## Implementation and Verification

- Added Entry.context() and a private generic Context using the existing Scope directly. Exposes Target, source, function/functions/ref/typeRef and define/select; Self = @This() composes selection without a new normalization path.
- Migrated callback, event-queue, io-streams and materialized to uppercase Context types and existing Entry declarations. Type references, decorations and member order are preserved.
- Added five permanent Context unit tests and seven compile-failure fixtures. Updated public docs, migration guidance and Unreleased notes.
- Before writing the examples, a temporary comparison compiled both the old declarations and the public Context rewrite; exact comptime deep equality passed for all four normalized bindings.
- zig test src/root.zig: 16/16 tests passed. zig build test --summary all: 318/318 steps and 765/765 tests passed.
- Each of the four examples passed test, go-check, go-lib, abi-check, go-coverage, purego-go-check and purego-go-lib, plus fresh cgo and CGO_ENABLED=0 Go tests. No generated files changed.
- Historical research reproducer now reads its original 755501c0 baseline explicitly; its 7 positive and 7 rejection checks passed again.
- A limited event-queue compile-only probe (build-obj -fno-emit-bin, forced binding evaluation, fresh local caches, shared global cache, 3 interleaved runs) measured median 0.512s/122.81 MiB RSS for legacy syntax and 0.507s/123.48 MiB for Context syntax. This is a local sanity check, not a general performance guarantee.
- zig fmt --check and git diff --check passed.
