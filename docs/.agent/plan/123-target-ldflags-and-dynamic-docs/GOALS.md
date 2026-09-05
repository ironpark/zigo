# GOALS

## Problem and the end result from the user's point of view

`cgo_flags.extra_ldflags` appends the same flags to every platform's link
line, so a flag one platform needs (`-ldl` on Linux, a framework on macOS)
cannot be added without affecting the others. Separately, `.cgo_dynamic`
trees fail `go test` on the host because the Go executable carries no rpath
to the install directory, and the docs only hint at the remedy.

After this plan, `cgo_flags.target_ldflags` lists `{ goos, goarch?, ldflags }`
entries that become one `#cgo <goos>[,<goarch>] LDFLAGS:` line each, and the
configuration docs show the rpath recipe for `.cgo_dynamic`.

## Measurable goals

- An entry `{ .goos = "linux", .ldflags = &.{"-ldl"} }` renders
  `#cgo linux LDFLAGS: -ldl` in the raw package, in both single- and
  multi-target trees, and also when the main line lives in the volatile file.
- Docs describe the option and the `.cgo_dynamic` rpath recipe.

## Supported scope and non-goals

Appending only; replacing a platform's whole line stays `cgo_flags.ldflags`.

## Reference source / commit / license

Own code.

## Completion criteria for the whole plan

`zig build test` passes with the extended snapshot case; docs and CHANGELOG
updated.
