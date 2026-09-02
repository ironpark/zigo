# GOALS

## Problem and the end result from the user's point of view

`pub fn init(gpa: Allocator, options: Options) !Terminal` is already boxed by zigo, but `Options` is a plain struct with defaults and non-C fields, so it is rejected and the downstream project writes `newTerminal`/`freeTerminal` by hand. The end result: `param_meta` may flatten a struct parameter: `.options = .{ .flatten = .{ "cols", "rows", "max_scrollback_bytes" } }`. The listed fields become individual Go parameters, the shim builds the struct with those fields set and every other field at its declared default.

## Measurable goals

- Flattened fields may be bool, int, float, registered enum, and optionals of those (Go gets a pointer or an `Option`-style value consistent with how optional scalars are already exposed, if at all; otherwise a diagnostic).
- Fields not listed must have a default value in the Zig struct, else a new diagnostic naming the field.
- Works for any function parameter, not only constructors; Go parameter names are the field names (respecting `params` order constraints: the flattened fields appear in place of the struct parameter).
- Generator case, example (extend the example that has a boxed value `init`), docs `bindings.md` under "값으로 반환하는 init" and "함수 메타데이터", CHANGELOG, `abi-diff` (adding a flattened field is breaking).

## Supported scope and non-goals

In scope: `walk.zig` param_meta schema and comptime struct default inspection, semantic IR representation (a `flatten` list on the parameter with leaf types), validate, lower, emit for both backends.
Non-goals: nested struct fields inside the flattened struct, slices/strings inside the flattened struct, flattening return structs.

## Reference source / commit / license

Current main; boxed value init in `walk.zig`/`emit.zig`; ZIGO027 params-count rule.

## Completion criteria for the whole plan

Phase done; full verification loop green; docs and CHANGELOG updated; tree clean.
