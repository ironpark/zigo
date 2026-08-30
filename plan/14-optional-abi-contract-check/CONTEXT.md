# SCOPE

Modify `src/gen/abi_diff.zig`, the public build API in `build.zig`, all examples that intentionally exercise compatibility checking, and the corresponding README/wiki/design documentation.

# CONTEXT

## Current implementation and bottlenecks

`abi_diff.diff` matches functions by logical name and compares types, ownership, retention, and errors, but never compares `SemanticFn.symbol`, document package/prefix/IR version, or constructors. `Options.abi_base` defaults to `HEAD` and `GoBindings.abi_check` is always non-null, making the policy look mandatory even for consumers that rebuild Zig and Go together.

## Target structure and invariants

The diff reports every generated binary or binding-surface identity change that is present in semantic IR. Compatibility checking exists only when the consumer supplies an ABI baseline configuration. Examples opt in explicitly so CI continues exercising the feature.
