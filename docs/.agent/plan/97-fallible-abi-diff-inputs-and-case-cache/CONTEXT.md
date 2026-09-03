# SCOPE

- Keep `abi-diff` output for valid inputs byte-identical.

# CONTEXT

## Current implementation and bottlenecks

- `abi_diff.zig` `lowerFor` calls `lower.semanticDocumentForBackend` after `stream_return.expand`; no validation runs on CLI inputs.
- `build.zig` `addGeneratorCases` (~line 764) iterates case directories and creates a `Run` step per case with `addDirectoryArg(cases.path(b, name))` plus an output directory arg.

## Target structure and invariants

- Every CLI entry point rejects malformed input with a diagnostic; `unreachable` in lowering is reserved for validated documents.
- Test steps are cache-correct with respect to every file they read.
