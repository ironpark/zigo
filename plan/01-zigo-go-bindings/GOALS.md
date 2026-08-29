# GOALS

## Problem and the end result from the user's point of view

Exposing a Zig library to Go today means hand-writing an `export fn` shim that lowers
slices, optionals and error unions to a C ABI, a matching C header, cgo wrappers with
`-L`/`-I` paths, and pointer lifetime management — then redoing all of it whenever the
Zig API changes.

After this plan, a Zig library author adds zigo as a package dependency, declares which
declarations to expose in one `bindings.zig` file, and runs `zig build go`. The C ABI
shim, the C header, a raw cgo package and an idiomatic Go package are generated, the
static library is built, and CI can enforce both that the generated files are current
and that the ABI has not broken.

The library source is never modified: no `export`, no annotations.

## Measurable goals

- A Zig library author wires zigo in with one call, `zigo.addGoBindings(b, .{...})`.
- Four example projects (scalar, errors, opaque, callback) build and pass `go test`.
- Zig source is never parsed for type information; all types come from `@typeInfo`.
- Every one of the nine rejection conditions produces a diagnostic with a source
  location and a fix hint, and produces no output files.
- `zig build go-check abi-check` works as a CI gate.
- Repeated create/destroy cycles leak zero bytes under a counting allocator.

## Supported scope and non-goals

Supported: Go only; native target; static linking; scalars, enums, slices, optionals,
error unions, opaque handles, extern/packed structs, explicitly specialized generics,
and callbacks.

Non-goals: languages other than Go; a standalone installable binary; cross-compilation;
tagged unions; exposing allocators to Go; dynamic-library distribution.

## Reference source / commit / license

No upstream source is being ported. The design is specified in this repository:
`docs/00-constraints.md`, `docs/01-architecture.md`, `docs/02-ir-spec.md`,
`docs/03-lowering-rules.md`, `docs/04-implementation-plan.md`.

Toolchain: Zig 0.16.0, Go 1.26.

## Completion criteria for the whole plan

- All four examples build from a clean checkout and pass `go test ./...`.
- `zig build test` passes: reflector JSON goldens, lowering goldens, emitter goldens,
  and diagnostic snapshots.
- `zig build go-check` fails on a stale generated tree; `zig build abi-check` fails on
  a breaking change and passes on an additive one.
- A Go consumer can `go get` an example's Go module and build it without Zig installed.
