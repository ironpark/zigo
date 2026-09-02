# GOALS

## Problem and the end result from the user's point of view

Reading a scalar field of an opaque type is the most common binding operation, yet zigo binds only functions. Downstream projects write facade functions (`pub fn cols(self: *Terminal) u16 { return self.cols; }`, `cursorX` reaching into `self.screen.cursor.x`) for every field. The end result: an opaque type registration may list `.fields`, each with a dotted `.path` into the Zig struct, an optional Go `.name`, and `.set = true` for a setter. zigo generates the shim getter/setter, the C symbol, and the Go method without touching the upstream type.

```zig
.{ .type = gostty.Terminal, .repr = .@"opaque", .fields = .{
    .{ .path = "cols" },
    .{ .path = "rows" },
    .{ .path = "screen.cursor.x", .name = "cursorX" },
    .{ .path = "screen.cursor.style", .name = "cursorStyle", .set = true },
}},
```

## Measurable goals

- Getters for bool, integer, float, and registered enum fields on an opaque type, addressed through dotted paths that cross plain struct fields (by value or through non-optional single pointers).
- Setters when `.set = true`, same type set.
- Anything else (slices, optionals, unions, unregistered enums, pointers to non-struct, packed fields whose backing is not addressable) is rejected with a new `ZIGO0NN` diagnostic at the reflect stage that names the path and the offending field type.
- Generated Go names: getter `Cols()`, setter `SetCols(v)`; `.name` overrides the getter stem. Collisions with functions go through the existing ZIGO024/ZIGO036 checks.
- Field accessors appear in semantic.json, lower to plain functions, and flow through cgo and purego, `abi-check`, `abi-diff` (adding a field accessor is compatible append), and the Go doc comment carries the Zig path.

## Supported scope and non-goals

In scope: `src/reflect/walk.zig` (comptime path walk with `@field`, `@typeInfo` on each hop), `src/gen/ir/semantic.zig` (a field-accessor origin marker on `SemanticFn` or synthesized functions with a flag), validate, lower, emit, generator cases, an example (extend 02 or the example that already has an opaque struct with scalar fields), docs `bindings.md` new section, CHANGELOG.
Non-goals: struct-valued getters (use `.repr = .value` types later), field access on tagged unions, atomic or volatile fields, packed struct bitfields other than integer-backed enums and integers that Zig can load with `@field`.

## Reference source / commit / license

Current main. Similar synthesis exists for boxed value `init` (plan 23ae001 era) and constructors from `.constructs`; reuse how synthesized functions are named and given C symbols.

## Completion criteria for the whole plan

All phases done; `zig build test --summary all`, `zig fmt --check build.zig src tests examples`, all 11 examples on cgo and purego green; docs and CHANGELOG updated; tree clean.
