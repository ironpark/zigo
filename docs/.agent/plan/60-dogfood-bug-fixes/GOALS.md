# GOALS

## Problem and the end result from the user's point of view

Real-world use of zigo (dogfooding in another project) surfaced four defects:

1. A non-constructor-named method declared with `.returns = .caller` returning an opaque
   pointer generates Go that returns the raw `unsafe.Pointer` where the signature says
   `*Feature`, a compile error, with no diagnostic. Users are forced to rename their API
   around `init/create/new/open`.
2. The `PublishGeneratedGo` prune walk covers the entire `go_dir` with no skip for
   `.zig-cache`/`zig-out`. When `go_dir` contains the build root, prune first deletes
   cached generator outputs, then on the next cache hit (empty `published` set) deletes
   the real committed `*_gen.go` files. Confirmed data loss in the field.
3. `typeNode` in src/reflect/walk.zig has no `.optional` branch, so `?*const T`
   parameters hit an unrelated `@compileError`. Nullable opaque-pointer params (e.g. a
   cancel token) cannot be expressed, even though semantic IR already models
   `opaque_ptr.nullable`.
4. Generated Go doc comments double the name: `writeGoDoc` unconditionally prefixes the
   Go identifier, and Zig docs that start with the declaration's own name render as
   `// AlgorithmID algorithmId names ...`.

End result: factory methods work under any name, prune can never touch cache or
out-of-tree files, optional opaque-pointer parameters are supported end to end, and doc
comments read cleanly.

## Measurable goals

- A fixture/example method named e.g. `openFeature` (not a constructor name) with
  `.returns = .caller` generates Go that compiles and returns an owned handle wrapped by
  `newX(...)`, with Close/cleanup identical to constructor-produced handles.
- Prune and `zigo check` walks skip `.zig-cache` and `zig-out` directories at any depth;
  a regression test proves a marker-bearing file inside `go_dir/.zig-cache` survives
  prune.
- A `?*opaque` / `?*const opaque` parameter reflects, validates, and generates: Go side
  accepts a nil-able owned handle (nil passes NULL), native side receives null. Covered
  by a fixture or example with a passing test on both cgo and purego goldens.
- No generated doc comment repeats the declaration name; when the Zig doc's first word
  is the declaration's own name (any case convention), it is replaced by the Go name
  instead of prefixed. Goldens updated via the case runner + `zig build snapshot
  --update-snapshots`.
- `zig build test` green; CI green on all jobs.

## Supported scope and non-goals

In scope: src/reflect/walk.zig, src/gen/emit.zig, src/gen/validate.zig (if a new
diagnostic is warranted for unsupported caller-return payloads), build.zig
PublishGeneratedGo, src/gen/sync_check.zig, goldens/fixtures/examples/docs affected.

Non-goals: optional non-pointer types (`?i32`, `?[]u8`) stay rejected (clear diagnostic
is fine); a Go `context.Context` convention (separate future work); changing the
constructor-name heuristic for functions WITHOUT explicit `.returns` metadata.

## Reference source / commit / license

Verified findings with file:line references recorded in the conversation (2026-09-02):
walk.zig:553 (name-based constructor set), walk.zig:163 (ownership metadata),
emit.zig:3909/2098/3162 (constructor-only wrapping paths), build.zig:845-940
(PublishGeneratedGo prune), sync_check.zig:49-63, walk.zig:310-415 (typeNode, no
.optional; :348 hardcodes nullable=false), emit.zig:3458-3489 (writeGoDoc prefix).

## Completion criteria for the whole plan

All four defects have regression coverage, goldens and docs are updated, and
`zig build test` plus full CI pass.
