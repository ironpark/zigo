# SCOPE

- `src/gen/emit/handles.zig`, `src/gen/emit/raw.zig`.

# CONTEXT

## Current implementation and bottlenecks

`writeParentLookup` declares then assigns; the borrowed `zigoAcquire` template unlocks in each branch; `raw.zig` emits `var xZero C.T; xPtr := &xZero; if len(x) != 0 {...}` for every slice; imports are single statements; the Close doc has a fixed sentence.

## Target structure and invariants

`parent := x.owner`; the second locked section of `zigoAcquire` computes `(ptr, err)` and unlocks once, releasing the parent only on error; a generic `zigoSlicePtr[T]` and `zigoStringPtr` in the cgo raw file replace the inline pattern (emitted only when used); grouped `import (...)` after `import "C"`; the Close doc names the `*HandleInUseError` case.
