# SCOPE

Contract versioning, validation context, build configuration, ordering, built-in module isolation, run-owned facts and public type/file/package rendering hooks. No release or consumer dependency bump.

# CONTEXT

The reviewed baseline is d148a2dc. Built-ins import emitter internals and lowering owns Must policy. Rendering is repeated during helper discovery; render callbacks must be deterministic.
