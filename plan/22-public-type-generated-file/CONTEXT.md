# SCOPE

In scope: emitter paths/renderers, build graph generated-file lists, generator atomicity and layout tests, golden fixtures, eight examples, and generated-file documentation. Out of scope: ABI semantics and API naming.

# CONTEXT

## Current implementation and bottlenecks

`renderPublic` currently writes enums, callback types, opaque handles, refs, lifecycle methods, and callable wrappers together. `build.zig` knows only the public, errors, helpers, and raw Go files, so adding a renderer alone would leave formatting, updates, and stale checks incomplete.

## Target structure and invariants

`renderPublicTypes` owns every public type declaration and any methods intrinsic to those types. Cross-file Go references remain package-local and unchanged. All emitters finish before generator output is committed, preserving generation atomicity.
