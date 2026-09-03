# SCOPE

- Promotion is per element with the same range check as whole parameters.

# CONTEXT

## Current implementation and bottlenecks

- `validate.zig` near line 1370 rejects narrow ints in slice positions; the shim has no per-element conversion loop.

## Target structure and invariants

- The Go surface never sees a non-standard width; the shim owns the conversion.
