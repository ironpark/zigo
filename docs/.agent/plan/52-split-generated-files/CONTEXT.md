# SCOPE

Files expected to change: `src/gen/emit.zig` (path helpers + routing render
passes to per-file writers + per-file import computation),
`src/gen/naming.zig` (deterministic union file-name derivation avoiding the
reserved suffixes `type`, `errors`, `helpers`, `runtime`, `enums`,
`handles`), `src/gen/generator.zig` tests, golden fixtures under `tests/`,
and every `examples/*/go*` tree. The public Go API of generated packages is
unchanged; the file set within generated packages changes (breaking only for
tooling that hard-codes generated file names).

# CONTEXT

## Current implementation and bottlenecks

- `emit.zig` (3,651 lines) already renders the type file in discrete passes:
  `renderPublicTypes` (enums), `renderGoHandles`, the shared runtime block
  (`zigoHandle`, `zigoCheckedPointer`, `zigoOptionalPointer`,
  `zigoProjectionError`, `zigoMust`, `zigoMustMatch`, projection status
  consts), `renderPublicTaggedUnionAccessors`, `renderPublicSnapshots`,
  `renderPublicUnionVariants`. They currently share one writer targeting
  `publicTypePath` (emit.zig:78-82).
- File-path helpers for all emitted files sit together at emit.zig:67-93.
- `sync_check.zig` diffs the staged generated tree against on-disk `*_gen.go`
  and prunes obsolete files automatically, so renamed/removed generated files
  need no manifest work.
- Plan 49 established the no-empty-file rule; `generator.zig:197-199` asserts
  absent files for a program that declares nothing.
- Plan 51 added deterministic identifier-collision resolution in
  `naming.zig` (suffix then numeric), reusable as the pattern for file names.

## Target structure and invariants

- Per public package: `<pkg>_gen.go` (operations, unchanged),
  `<pkg>_errors_gen.go` (unchanged), `<pkg>_enums_gen.go`,
  `<pkg>_handles_gen.go`, `<pkg>_runtime_gen.go`, and
  `<pkg>_union_<union>_gen.go` per tagged union. `<pkg>_helpers_gen.go`
  disappears; its content (e.g. `boolToUint8`) moves into the runtime file.
- Union file names derive from the Zig union name via `naming.zig` with a
  deterministic scheme; the `_union_` segment already prevents clashes with
  reserved suffixes, and residual clashes (two unions normalizing to the same
  file name) resolve deterministically with a numeric suffix.
- Each file computes its own import block from what it actually renders;
  every emitted file passes `gofmt` untouched.
- A file is emitted only if it contains at least one declaration.
- Declaration order within each concern is preserved from today's emission so
  content diffs against the pre-split concatenation are reviewable.
- cgo and purego emission stay in lockstep; goldens cover both.
