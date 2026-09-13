# GOALS

## Problem and the end result from the user's point of view

zigo's four public surfaces (bindings DSL, build.zig/CLI, generated Go API, plugin API) each carry
several spellings for the same concept, dead re-exports, stale doc comments, and generated Go that
exports internals. A binding author should find exactly one way to express each declaration, one
set of build options without hidden interactions, and generated Go that reads like a hand-written
Go package. Breaking changes are explicitly allowed; no compatibility aliases are kept.

## Measurable goals

- Every DSL concept has one spelling; removed synonyms fail to compile.
- `zig build test`, all example `zig build go-verify` targets and `go test ./...` pass after each phase.
- Generated Go handles export no `Zigo*` methods; raw packages always live under `internal/`.
- Docs and doc comments reference only APIs that exist.

## Supported scope and non-goals

In scope: names, option shapes, defaults, generated identifier rules, docs and examples.
Out of scope: new features, ABI changes to the C shim, Rust emitter feature parity beyond naming.

## Reference source / commit / license

Baseline commit ff6ef44d on main. MIT.

## Completion criteria for the whole plan

All five phases done; CHANGELOG records every rename in a "breaking" section with old → new tables.
