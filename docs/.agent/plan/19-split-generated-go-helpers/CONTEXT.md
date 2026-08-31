# SCOPE

Add the helper emitter and path, thread a fourth Go output through `addGoBindings`, refresh fixtures and eight examples, and document the four-file generated Go layout.

# CONTEXT

## Current implementation and bottlenecks

`renderPublic` appends private helpers after all public declarations and owns `sync/atomic` solely for callback accounting. The build graph currently formats and copies raw, public API, and public error files.

## Target structure and invariants

The main file retains declarations that define or implement the public API. The helper file owns only private runtime support and imports `runtime/cgo` and `sync/atomic` when callbacks exist. An empty valid helper file keeps the generated output set deterministic. The new emitter remains inside prepare-before-write generation and directory-wide stale checking.
