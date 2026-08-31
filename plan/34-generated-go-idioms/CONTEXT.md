# SCOPE

This plan changes `src/gen/naming.zig`, the emitters, the generator case fixtures, every committed
generated Go file, the build option surface for the package name, and the documentation. It does
not change the C header, the Zig shim, `semantic.json`, or `errors.lock.json`.

# CONTEXT

## Current implementation and bottlenecks

- `naming.zig` already has `snakeAlloc`, `pascalAlloc` and `camelAlloc`, and the emitters use them
  for function and type names. Parameter names are written straight from `abi.Program`, which
  carries the Zig spelling, so `source_len` and `input_name` reach the public API.
- No emitter checks a parameter name against Go keywords. A Zig parameter named `type` emits
  `func Pick(type int32)`, which does not parse; `build_options.isGoKeyword` already exists but is
  only applied to package names.
- Callback type names concatenate the function name, the parameter name and a `Callback` suffix,
  which produces `ApplyCallbackCallback` when the parameter is itself called `callback`.
- Receivers are derived twice: the function emitter uses the first letter of the type, the type
  emitter uses `value`, so one type has two receiver names across its generated files.
- Zig doc text is appended after the Go identifier without adjusting its first letter, so a doc
  sentence starting with a capital verb reads `// Echo Echoes ...`.
- `build.zig`'s `formattedGoSources` pipes each generated file through `gofmt` and silently falls
  back to the unformatted text when the binary is missing, so committed output depends on the
  machine. The emitters rely on that pass to expand one-line `if` statements and to align struct
  fields.
- The helpers emitter always writes a file even when it has nothing to add, leaving five committed
  files that contain only a package clause.

## Target structure and invariants

- One naming helper turns a Zig identifier into a public Go parameter name: camelCase, escaped when
  it is a Go keyword or a duplicate, with the existing `p0` fallback unchanged.
- One receiver-name helper is used by every emitter that writes a method.
- Emitted Go is canonical `gofmt` output: expanded statements, sorted import groups, and aligned
  field and value blocks. `formattedGoSources` and the gofmt probes that exist only to serve it are
  removed once the emitters own formatting.
- An emitter that has nothing to write reports no file, and the ownership and staleness bookkeeping
  treats a previously written empty file as obsolete.
- The public package name comes from a new option, defaulting to today's snake_case derivation,
  validated as a Go package name.
