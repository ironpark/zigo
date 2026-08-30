# GOALS

## Problem and the end result from the user's point of view

The generator currently relies on implicit arena lifetimes and global page allocators, has allocation-failure paths that can suppress validation, duplicates module wiring, and provides limited diagnostics when generated trees differ. Harden these boundaries and make generator behavior easier to test and maintain.

## Measurable goals

- Allocation failure cannot turn a semantic validation error into success.
- Generator scratch allocations have one explicit lifetime and allocation-bearing report builders clean up partial failures.
- Generator cases can be added as directory fixtures and selected with a build test filter.
- Build module wiring has one canonical construction path.
- Snapshot failures show useful content differences, and CI checks formatting plus compilation before the full suite.

## Supported scope and non-goals

Scope covers generator memory ownership, validation and emission allocation paths, generator test organization, build graph construction, snapshot diagnostics, CI quality gates, and small generator CLI diagnostics. It does not adopt zls LSP architecture, tracing, WASM execution, or broad release packaging changes.

## Reference source / commit / license

Engineering patterns are informed by the ignored local reference checkout `ref/zls` at commit `3e0d082084be43e36865136a138c1fe2023b33ca` (MIT). Implementations will be original to this repository; no source text will be copied.

## Completion criteria for the whole plan

All phases are done, formatting checks pass, the compile-only check passes, and `zig build test --summary all` passes without leaks or misleading failure output.
