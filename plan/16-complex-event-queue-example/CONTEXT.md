# SCOPE

Create the example build files, Zig implementation and binding declaration, Go
tests and generated artifacts, documentation, and CI list entry. Generator changes
are permitted only when the example reveals a real existing-contract defect.

# CONTEXT

## Current implementation and bottlenecks

`05-pipeline` is the only application-shaped example and concentrates on generic
specializations plus a system library. The remaining examples isolate individual
features, leaving no second complex consumer to validate stateful capacity/error
behavior and custom raw-package placement together.

## Target structure and invariants

An `EventQueue` owns copied UTF-8 state and a retained observer callback. Enqueue
copies only scalar event data, capacity is bounded, processing consumes a batch in
order, callback panic becomes a typed error, and `Close` releases callback/queue
state exactly once. Generated raw code lives under `go/bridge/cgo`.
