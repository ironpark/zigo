# GOALS

## Problem and the end result from the user's point of view

Generated Go wrappers currently validate tagged-union projections but pass ordinary opaque receivers and opaque arguments directly to cgo. Users therefore see inconsistent behavior after `Close`, and projection failures are only available as string panics. Build setup also requires repetitive step wiring, while reflection results and environment prerequisites are not inspectable through dedicated user-facing steps. Exported generated identifiers lack complete GoDoc coverage.

## Measurable goals

- Every generated call that consumes an opaque receiver or argument rejects nil, closed, and invalid borrowed handles before entering cgo.
- Tagged-union projections expose checked methods returning typed errors while existing convenience methods remain source compatible.
- A single public build helper registers generation, stale-check, report, doctor, and optional ABI-check steps.
- Report and doctor steps explain the effective binding contract and validate local Go/cgo/tool prerequisites.
- Every exported generated Go type, constant, variable, function, and method has useful GoDoc describing ownership and failure behavior where relevant.

## Supported scope and non-goals

This plan preserves existing public method signatures and generated filenames, keeps ABI diff opt-in, and retains the documented rule that concurrent `Close` and method calls on the same handle require caller synchronization. It does not add cross compilation, automatically delete obsolete generated files, or broaden the set of Zig types supported by lowering.

## Reference source / commit / license

The implementation is based solely on this repository at the starting worktree state. The Zig 0.16.0 standard library is used as the API reference; no external source is copied.

## Completion criteria for the whole plan

All phases are done, `zig build test` passes without misleading expected-failure output, all example generation/stale/ABI steps pass, every example Go module passes `go test ./...`, generated artifacts are current and formatted, and user documentation describes the new safety, diagnostics, and GoDoc contracts.
