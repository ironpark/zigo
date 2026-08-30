# SCOPE

Modify the emitter, generator orchestration, consumer build graph, snapshots/golden artifacts, eight examples, and user/developer documentation required by the output contract.

# CONTEXT

## Current implementation and bottlenecks

`renderPublic` emits enums, errors, handles, functions, and helpers into one writer. `emit.all` and `addGoBindings` only know one public Go output, so adding a renderer alone would omit formatting, source updates, and stale checking.

## Target structure and invariants

The main file retains enums, handles, functions, and non-error helpers. The error file owns all error declarations and imports the raw package only when error conversion needs it. Both files use package-derived snake-case names, participate in the same prepare-before-write generation transaction, gofmt stage, update step, and directory-level stale check. Empty error surfaces still produce a valid generated package file for a stable output set.
