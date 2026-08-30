# SCOPE

Update the build graph helper and architecture/user documentation, then verify all generated layout modes through existing examples.

# CONTEXT

## Current implementation and bottlenecks

The generator writes Go text directly into its cached output directory, and `UpdateSourceFiles` plus `go-check` consume that directory without an external formatter stage.

## Target structure and invariants

Each generated Go file is an input to a cacheable `gofmt` process whose stdout becomes a separate formatted file. A cached directory containing those files feeds both updates and stale checks. If `gofmt` cannot be found, the original generator directory is used unchanged.
