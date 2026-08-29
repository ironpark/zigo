---
depends_on:
- "01-zigo-go-bindings#3"
perf_phase: false
status: planned
---
> DONE-WHEN: `cd examples/01-scalar && zig build go && cd go && go test ./...` passes, asserting
> NEXT: none

# Vertical slice: Go calls Zig

## Planned Work

- Connect the generator's output directory to `UpdateSourceFiles` so generated files
  land in `go_dir` in the source tree.
- Build the static library from the generated shim plus the user module and install it,
  along with the header into the install prefix.
- Generate `cgo.go` link directives as `${SRCDIR}`-relative paths computed from `go_dir`
  and the install prefix; never emit absolute paths.
- Bootstrap `go.mod` in the example if absent.
- Make `examples/01-scalar` pass `go test`.

## Done When

- `cd examples/01-scalar && zig build go && cd go && go test ./...` passes, asserting
  `Add(3, 7) == 10`.
- Generated files are present in the source tree and contain no absolute paths.
- Deleting `zig-cache` and rebuilding reproduces the identical generated tree.
