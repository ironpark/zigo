# GOALS

## Problem and the end result from the user's point of view

A `.callback` whose signature carries a registered enum or a handle pointer (`*Stream`) generates Go correctly but the shim's trampoline is spelled with the wire scalar (`i32`, `Stream` by value), so `zig build` fails. A callback parameter of slice or string type is accepted by validation and then panics `zigo-gen` at `type_spelling.zig:71`. After this plan both enum and handle-pointer callback parameters compile, and unsupported callback parameter types are refused with a sited diagnostic.

## Measurable goals

- Generator case with an enum parameter, an enum result, and a `*Handle` parameter in a callback signature produces a shim that compiles against a Zig target module on cgo and purego.
- A callback carrying `[]const u8`, `[*:0]const u8`, an extern struct, an optional, or a by-value opaque is reported as a ZIGO057 diagnostic instead of a panic.

## Supported scope and non-goals

In scope: shim thunk/trampoline spelling, cgo export spelling, purego dispatcher spelling, a new validation rule, docs and changelog. Not in scope: carrying slices or strings through callbacks (a separate feature).

## Reference source / commit / license

Report from the gostty binding (ghostty), items B and C. No external code.

## Completion criteria for the whole plan

`zig build test` passes with the new generator cases and validation tests; the reproduction documents in `/tmp/zigo-repro` generate a compiling shim or a diagnostic.
