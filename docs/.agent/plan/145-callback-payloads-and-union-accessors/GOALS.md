# GOALS

## Problem and the end result from the user's point of view

Callbacks can only carry wire scalars, so a binding that wants to hand text or bytes to Go has to park the request on a handle and expose accessors. A tagged union returned by value exposes only its tag. After this plan a `[*:0]const u8` or a `[*]const u8` + `usize` pair in a callback signature is a Go `string` (or `[]byte`), and a value union has `As<Variant>()` readers.

## Measurable goals

- A callback `*const fn (name: [*:0]const u8, data: [*]const u8, len: usize, userdata: usize) callconv(.c) void` generates `func(string, string)` on cgo and purego, and the example's Go tests observe the copied text.
- `.params = &.{ .{ .semantic = .opaque_bytes } }` on the registered callback makes the pair a `[]byte`.
- `CurrentViewport()` results expose `AsRgb() (RGB, bool)` in the tagged-union example.

## Supported scope and non-goals

Byte payloads only (`u8` element); other element types stay refused by ZIGO057. Payloads are copied into Go memory at dispatch, so no retention option is needed yet. A Variant type switch for value unions is not in scope.

## Reference source / commit / license

gostty feature requests 1 and 2. No external code.

## Completion criteria for the whole plan

`zig build test` passes; examples 04-callback and 10-tagged-union pass their Go tests on cgo and purego.
