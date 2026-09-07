# SCOPE

Public schema/DSL, normalization into the generator's internal declarations, plugin target validation, examples/fixtures/documentation and regression tests. Preserve supported native/Go behavior. No release or push is part of this task.

# CONTEXT

The user explicitly waived compatibility and requested implementation of the redesign. The existing reflection/emission model remains an internal lowering target, not a second public authoring API. Parameter selectors use original Zig argument indices; source-name lookup is not guessed from unavailable comptime names. Existing supported lifetimes (owned, borrowed receiver, constructor parent) are represented explicitly; inventing new lifetime runtime behavior is out of scope.
