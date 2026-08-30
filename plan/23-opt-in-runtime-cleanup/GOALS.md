# GOALS

## Problem and the end result from the user's point of view

Generated owning Go wrappers currently leak native resources and retained callback handles when callers omit `Close`. Provide an explicit Go 1.24+ option that attaches `runtime.AddCleanup` as a best-effort fallback without weakening the deterministic `Close` contract.

## Measurable goals

- Propagate `.auto_cleanup = true` from `addGoBindings` through the CLI and generator.
- Generate cleanup arguments that cannot reach the wrapper, stop cleanup during explicit `Close`, and keep wrappers alive across native calls.
- Demonstrate cleanup of native allocations and retained callback handles in the event-queue example.

## Supported scope and non-goals

The feature applies only to caller-owned opaque types that have a generated deinitializer. It is disabled by default and requires Go 1.24 or newer. It does not guarantee cleanup before process exit, replace `Close`, resolve callback closures that retain their owner, or model thread-affine deinitializers.

## Reference source / commit / license

Repository implementation at commit `40936e7`; semantics follow the Go standard library `runtime.AddCleanup` contract and `os.Process` resource-state pattern under the Go BSD license, without copying implementation code.

## Completion criteria for the whole plan

Opt-in generated code compiles and passes forced-GC, explicit-close, stale-generation, ABI, native, Windows, and Go tests while default output remains Go 1.23 compatible.
