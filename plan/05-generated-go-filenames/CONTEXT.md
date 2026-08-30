# SCOPE

Change the emission path contract and consuming build paths atomically, migrate checked-in example outputs, and document the naming rule.

# CONTEXT

## Current implementation and bottlenecks

`emit.publicPath` writes `<package>/generated.go`, `emit.rawPath` writes `internal/raw/cgo.go`, and `build.zig` duplicates both strings when copying generated files into source trees. Existing example files must be removed during migration or Go compilation will see duplicate declarations.

## Target structure and invariants

The normalized Go package name is the filename stem. Public package `scalar` receives `scalar/scalar_gen.go`; internal package `raw` receives `internal/raw/raw_gen.go`. All generated Go filenames end in `_gen.go`, while contents and package declarations remain unchanged.
