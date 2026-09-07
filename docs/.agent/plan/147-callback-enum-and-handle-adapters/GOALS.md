# GOALS

## Problem and the end result from the user's point of view

0.16.0 fixed the shim thunk for callback enums (`@intFromEnum`/`@enumFromInt`) but the Go
side still stores the user's function under the public spelling while the raw dispatcher
asserts the wire spelling. Two user-visible failures follow:

- B: a callback signature mixing an enum with a position that already needs an adapter
  (`bool`, packed value, string) fails to compile: the adapter receives the enum as its raw
  integer and passes it straight through. An enum-only signature compiles but the raw
  layer's `state.Fn.(func(int32))` assertion does not match the stored `func(Enum)`.
- C: a handle pointer parameter (`*Stream`, `?*const Stream`) produces the Go type
  `func(*Stream)` but the raw layer asserts `func(unsafe.Pointer)`, so the first native
  invocation panics with an interface conversion error.

After this plan, `func(DragEvent, string, DragOperation, bool)` and
`func(*ClipboardRequest)` callbacks compile and dispatch on cgo and purego, with the
handle parameter delivered as a borrowed, owner-less handle.

## Measurable goals

- The `callback_enum_handle` and `callback_enum_handle_purego` goldens store adapters whose
  parameter and result types match the raw dispatcher's assertion exactly.
- An example Go test drives an enum + handle callback through the real native library on
  both backends and passes.

## Supported scope and non-goals

In scope: enum parameters and results (with or without a `.go` adapter), nullable and
non-nullable handle pointer parameters, both backends, docs and changelog. Out of scope:
handle results from callbacks, value-typed handles (still ZIGO057).

## Reference source / commit / license

Own code; no external reference.

## Completion criteria for the whole plan

`zig build test` passes, the goldens are regenerated, `examples/04-callback` passes
`go-check`, `go test` and the purego equivalents, and docs describe the new behaviour.
