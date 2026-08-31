# GOALS

## Problem and the end result from the user's point of view

An opt-in tagged union can be registered once in `zigo.define`; zigo then emits a stable tag enum and checked payload accessors automatically. Zig union layout never crosses the C ABI.

## Measurable goals

- Reflect all variants, discriminant values, and supported payload types into semantic IR.
- Emit `Tag()` and `As<Variant>() (payload, bool)` APIs for owned and borrowed handles.
- Reject direct by-value union use, unsupported payloads, and generated-name collisions with actionable diagnostics.
- Demonstrate and execute the feature in a real example from Zig through C/cgo to Go.

## Supported scope and non-goals

Support tagged-union handles registered with `.repr = .tagged_union`, including void, scalar, enum, opaque-pointer, and scalar-slice payloads. Direct union-by-value ABI exposure, automatic allocation/copying, mutation setters, and untagged unions are out of scope.

## Reference source / commit / license

Repository implementation on the current branch. Zig 0.16.0 type reflection and C ABI guidance are the language reference baseline; no external source is copied.

## Completion criteria for the whole plan

Semantic, validation, lowering/emission, ABI diff, generated golden artifacts, documentation, Zig tests, and Go integration tests all agree on the accessor contract, and the complete root test graph passes.
