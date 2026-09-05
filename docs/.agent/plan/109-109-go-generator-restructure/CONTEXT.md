# SCOPE

- `src/gen/emit.zig` split into `src/gen/emit/` by output file.
- `src/gen/validate.zig` split into `src/gen/validate/` by concern with an ordered rule list.
- `src/gen/lower.zig` and `src/gen/ir/abi.zig` gain the fields that replace emit's shadow predicates.
- `src/main.zig`, `src/gen/generator.zig` call the Must-variant check on the lowered program.
- `build.zig` keeps the consumer API; repository test wiring moves to `build/`.
- `src/reflect/names.zig` scans each source file once per run.
- `docs/development.md` updated.

# CONTEXT

## Current implementation and bottlenecks

- `emit.zig` sections in order: lifecycle/shim (259-1715), header (1716-2049),
  raw types and cgo raw (2050-3027), purego raw (3028-4251), raw callbacks
  (4252-4770), must variant and public package (4771-7000), shared type writers
  and predicates (7000-10000), tests (10000+). Everything is file-private, so a
  split has to make cross-file helpers `pub`.
- Thirteen `programUses*` / `structConversion*` / `nodeUsesBoolHelper`
  predicates re-derive emitter branch structure to decide whether a helper is
  referenced. `renderPublicFile` already renders the body first and reads the
  imports off the text; that discipline is not applied to helpers.
- The Must-variant rule lives in `emit.zig:5323` (lowered program,
  `needs_check`) and `validate.mustVariantEligible` (semantic document); they
  disagree on callback signatures flagged elsewhere.
- `AbiFn.MaterializedReturn/Out` carry a layout name; `emit.materializedLayout`
  resolves it with a linear scan and `unreachable`.
- `validate.findIssue` is one 600-line function of rule-major loops; the order
  of loops is the diagnostic priority and tests depend on it.
- `build.zig` mixes `addGoBindings` (consumer API, ~350 lines) with process
  contract tests, generator cases, golden checks and module wiring.
- `names.apply` and `names.applyCoverageImports` each read and parse the root
  source; imports reached from both are parsed twice.

## Target structure and invariants

- `src/gen/emit/` root `emit.zig` exports `Options`, `Emitter`, `core_emitters`,
  `public_emitters`, `unionFilesAlloc`, `packageMatches`; sibling files own one
  output each and import `common.zig` for type writers and names.
- Lowering records per-function decisions on `AbiFn`: `must_variant`, the
  materialized layout index. Emit and validate read, never re-derive.
- Helper emission is decided by scanning rendered bodies for the helper's
  spelled name, via one `ReferencedHelpers` pass shared by raw and public files.
- Diagnostic priority order is unchanged: rules stay rule-major, listed once.
- Generated output is byte-identical at every phase boundary.
