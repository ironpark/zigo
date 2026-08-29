# SCOPE

In scope, in this repository:

- `build.zig` as zigo's public API surface, exporting `addGoBindings`.
- Module `zigo`: the `zigo.define` binding-declaration DSL.
- `src/reflect/`: the reflector root, compiled into the user's build graph, which walks
  the comptime type graph and writes `semantic.json` plus `layout.json`.
- `src/gen/`: the `zigo-gen` executable — a pure function from IR files to output files.
  Contains IR types, validation, lowering, the four emitters, and the ABI differ.
- `examples/`: four self-contained Zig + Go projects consuming zigo by relative path.
- `tests/`: IR fixtures and golden output trees.

Out of scope: everything under "non-goals" above, plus editor tooling, package
registry publishing, and a Go module proxy story beyond committing generated files.

# CONTEXT

## Current implementation and bottlenecks

The repository holds the `zig init` scaffold — `src/root.zig` and `src/main.zig` with a
`run` step and two test steps — and the five design documents listed above. No zigo code
exists yet.

Two facts drive the whole design and are established in `docs/00-constraints.md`:

- `@typeInfo(@TypeOf(f)).@"fn".params` carries `is_generic`, `is_noalias` and `type`,
  but no `name`. Parameter names cannot come from reflection, so they must be supplied
  by the sidecar `.params` tuple, recovered from the AST as a best effort, or fall back
  to `p0, p1, ...`.
- A generic function has no readable signature before instantiation, so the explicit
  specialization list in `bindings.zig` is the only way to reach generic APIs.

The riskiest part of delivery is `addGoBindings` itself: it is the single surface every
user touches, and a wrong signature breaks every consumer's `build.zig`. It is therefore
designed against a real consumer — an example project — from the first phase.

## Target structure and invariants

The build graph, from `docs/01-architecture.md`:

    user module + bindings.zig
      -> module wiring (no source synthesis)
      -> reflector executable, run, stdout captured
      -> semantic.json / layout.json
      -> zigo-gen: validate -> lower -> emit
      -> shim.zig, C header, go/internal/raw, go/<pkg>
      -> UpdateSourceFiles (or --check) into the source tree
      -> static library + installArtifact

Invariants held throughout:

- The reflector observes; it never decides. Every judgement — whether a type may be
  exposed, which error code an error gets, how a slice is lowered — belongs to
  `zigo-gen`. This keeps the Zig-version-sensitive component thin.
- `zigo-gen` is a pure function: IR files in, output files out. It knows nothing about
  the Zig compiler or user code, which is what makes its tests fixture-only.
- Lowering happens once. The Zig shim, C header and Go emitters all read the same
  lowered `AbiFn`; if any of them re-derived the lowering the three artifacts could
  disagree on the ABI.
- Generated Go is committed to the user's source tree, because `go get` consumers do
  not have Zig, and gopls and `go build` need stable paths.
- Only `generated_`-prefixed files are written in the public Go package. A user-authored
  file for a type suppresses generation of that type's public layer while the raw layer
  keeps regenerating.
- Error codes live in a committed append-only `errors.lock.json`; `@intFromError` is
  never used because its values shift between builds.
