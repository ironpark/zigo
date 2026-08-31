# GOALS

## Problem and the end result from the user's point of view

CI currently regenerates bindings before checking them, masking committed stale output. CamelCase binding names also produce installed library and header names that disagree with the generator's snake_case cgo directives. Make stale output fail before mutation and make artifact naming consistent.

## Measurable goals

- `go-check` runs before `go` for every CI example.
- CI fails if generation changes tracked files or adds untracked files under `examples/`.
- A CamelCase binding name builds, installs, and links using one snake_case library/header stem.
- Zig tests and every example's Go tests pass.

## Supported scope and non-goals

Change the shared build integration, CI workflow, and add one focused CamelCase example. Do not change existing public Go package paths or redesign the generator CLI.

## Reference source / commit / license

The repository's current `build.zig`, generator naming helpers, example projects, and CI workflow are the implementation reference. No external source is incorporated.

## Completion criteria for the whole plan

Both regressions have automated coverage, all verification commands pass, the implementation is committed, and the phase is marked done.
