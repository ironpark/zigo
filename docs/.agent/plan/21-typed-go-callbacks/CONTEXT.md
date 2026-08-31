# SCOPE

Changes may touch Go emitter naming/rendering, generator tests, golden fixtures, generated example files, and callback documentation. Semantic and ABI IR formats remain unchanged.

# CONTEXT

## Current implementation and bottlenecks

Public signatures already enforce anonymous callback signatures, but the shared private helper accepts `any`. `cgo.Handle.Value` is asserted in a separate raw package, so directly storing a new public defined type would fail the raw package's unnamed function assertion and importing the public package would create a cycle.

## Target structure and invariants

Each callback role receives a deterministic public defined type such as `EventQueueObserver`. A private helper accepts exactly that type, explicitly converts it to the identical unnamed function type, and only then creates the handle. The raw trampoline continues asserting the unnamed type. Handle deletion and retained-handle ownership remain type-neutral.
