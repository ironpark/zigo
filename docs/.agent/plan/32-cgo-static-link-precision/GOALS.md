# GOALS

## Problem and the end result from the user's point of view

A project that registers both the `.cgo` and `.purego` backends installs a static archive and a
shared library with the same base name into one `zig-out/lib`. Generated cgo code links with
`-L<dir> -l<name>_zigo`, so the platform linker prefers the shared library and the cgo build fails
with undefined `zg_` symbols, or silently links the wrong artifact. Users should be able to build,
test and ship both backends from one build tree without ordering their commands or separating
install prefixes.

## Measurable goals

- Generated cgo code for `.link_mode = .static` names the archive it needs, so no other artifact in
  the same directory can satisfy the link.
- A single build tree that produces both backends passes the cgo Go tests and the `CGO_ENABLED=0`
  purego tests in either order.
- Generated files stay platform neutral: the same text is produced on macOS and Linux.
- The dynamic cgo path and user-supplied `cgo_flags` overrides keep their current behavior.

## Supported scope and non-goals

- Only the default (non-overridden) LDFLAGS of the generated cgo raw file change. Nothing changes
  for `.backend = .purego`, whose generated Go contains no cgo directives.
- Windows import-library naming is out of scope; zigo generates Go for native macOS and Linux only.
- Do not change the installed artifact names, install directories, or the shared-library contract.
- Do not restructure the examples that register the two backends differently; the toggle style in
  `examples/10-tagged-union` stays as it is.

## Reference source / commit / license

- Follow-up to plan `31-shared-library-purego`, phase 05, which documented this collision as a
  workaround instead of removing it.

## Completion criteria for the whole plan

- All generated cgo artifacts and golden fixtures are regenerated and current.
- `zig build test`, every example's `test go-check abi-check`, the cgo Go tests, and the purego
  `CGO_ENABLED=0` tests pass from one build tree with both backends installed.
- CI proves the single-tree dual-backend build, and the user documentation no longer prescribes a
  workaround that is no longer needed.
