# SCOPE

Add build metadata, Zig implementation and bindings, generated Go/IR/lock files,
Go tests, README, CI registration, and documentation. Fix generator defects only
if the broad surface reveals a reproducible existing-contract problem.

# CONTEXT

## Current implementation and bottlenecks

The largest current examples have roughly a dozen bound functions. They combine
features but do not stress large receiver namespaces, several enums and error sets,
or a generated Go file with dozens of methods.

## Target structure and invariants

A `TelemetryHub` owns its UTF-8 name, preallocated bounded samples, and retained
observer. Reject overflow is transactional; drop-oldest is explicit. Rename
allocates before replacing state. Processing removes a sample only after successful
observer delivery. Transform/query/stat APIs preserve capacity and ownership.
