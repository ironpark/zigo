# SCOPE

In scope: public build option, generator CLI/options, emitter lifetime code, generator tests, event-queue opt-in fixture, Go module version, documentation, and full verification. Out of scope: making cleanup the default and changing ABI metadata.

# CONTEXT

## Current implementation and bottlenecks

Owning wrappers store native pointers and retained `cgo.Handle` values directly and release them through `sync.Once` in `Close`. The generator defaults new modules to Go 1.23. Attaching cleanup directly to `Close` would self-retain the wrapper, and native calls currently lack `runtime.KeepAlive` because no asynchronous cleanup exists.

## Target structure and invariants

Cleanup receives an immutable value copy containing only the native pointer and callback handles, never the wrapper. Explicit `Close` keeps the wrapper reachable, stops the cleanup, invokes the same resource-release helper, and remains idempotent. Every wrapper call that passes a cleanup-managed owner to native code defers `runtime.KeepAlive`.
