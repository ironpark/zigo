# GOALS

## Problem and the end result from the user's point of view

Generated Go source currently uses generic `generated.go` and `cgo.go` names. Every generator-owned Go package should instead receive a predictable `<package>_gen.go` file, making generated ownership visible from the filename.

## Measurable goals

- Emit public bindings as `<normalized-package>/<normalized-package>_gen.go`.
- Emit the internal raw package as `internal/raw/raw_gen.go`.
- Update build graph source-copy paths, generator tests, examples, and documentation.
- Remove legacy generated filenames from every example so Go packages do not contain duplicate declarations.

## Supported scope and non-goals

Generator-owned Go filenames are in scope. Go package names, generated contents, ABI symbols, user-authored Go files, and non-Go generated artifacts are unchanged. Configurable filename overrides are not added.

## Reference source / commit / license

The current repository worktree at `0b86d07` is the reference. No third-party source is copied.

## Completion criteria for the whole plan

Unit tests assert the new paths, every example regenerates and passes Go tests, stale checks and ABI checks pass, documentation describes the new layout, and no legacy `generated.go` or `cgo.go` artifact remains in example Go trees.
