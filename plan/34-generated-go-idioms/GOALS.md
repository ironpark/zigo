# GOALS

## Problem and the end result from the user's point of view

The generated bindings compile, pass `go vet`, and their error design is sound, but the public Go
API does not read like hand-written Go. Parameter names keep Zig's snake_case
(`NewTelemetryHub(input_name string, max_samples uint, ...)`), a callback type is named
`ApplyCallbackCallback`, doc comments read `// Echo Echoes UTF-8 text`, receiver names for one type
differ between generated files, enum `String()` throws the value away, and a Zig parameter named
`type` or `range` generates Go that does not parse. Canonical formatting also depends on an
external `gofmt`: without it the emitted one-line `if` statements are committed unformatted, so the
same inputs produce different files on different machines.

The end result: a Go developer reading the generated package cannot tell it came from a generator,
and the same inputs always produce the same bytes.

## Measurable goals

- Public parameter names, callback type names, and receiver names follow Go convention, and any
  name that collides with a Go keyword or another parameter is escaped deterministically.
- Doc comments read as Go sentences that begin with the declared identifier.
- `String()` on a generated enum reports the numeric value for an unknown tag, and an unrecognized
  error code carries its number into the message.
- Generated files are byte-identical to their `gofmt` output, and generation no longer runs or
  requires the external `gofmt` binary.
- No empty generated file is written.
- A binding set can choose its public Go package name instead of accepting the snake_case default.

## Supported scope and non-goals

- Only names, comments, diagnostics, and formatting of generated Go change. The C ABI, the Zig
  shim, the semantic IR, lowering, the error codes and every function signature type stay as they
  are.
- Parameter names are not part of a Go call, so renaming them does not break callers. Renaming a
  callback type does, so keep the old name available where that is cheap.
- The default public package name stays as it is today; the override is opt-in because it changes
  import paths.
- Do not add `io.Closer` semantics, zero-copy string conversion, context parameters, or iterator
  helpers. Those are behavior changes, not idiom fixes.

## Reference source / commit / license

- Conventions: Go Code Review Comments, Effective Go, and staticcheck's ST1003 (naming), ST1016
  (receiver names), ST1020/ST1021 (comment form).
- `gofmt` behavior is the reference for canonical formatting, including field and value alignment
  inside a block.

## Completion criteria for the whole plan

- Every example regenerates, compiles, passes `go vet` and `gofmt -l` with no output, and its Go
  tests pass on both backends.
- A binding whose Zig parameters are named `type`, `range` or `func` generates code that compiles.
- Generation with no `gofmt` on `PATH` produces the same bytes as generation with it.
- The wiki documents the naming rules and the package name override.
