# GOALS

## Problem and the end result from the user's point of view

Everything that is true of Go rather than of the bound Zig library is spread
across the generator. `src/gen/naming.zig` holds the Go keyword list, the Go
identifier and package-name predicates, the Go parameter-name rule and the
`ZIGO_..._LIBRARY_PATH` variable rule beside genuinely neutral string
transforms. `src/gen/ir/semantic.zig` holds `publicFunctionNameAlloc`, the one
rule for a public Go name, inside the IR that is supposed not to know the
output language. `src/main.zig` runs `gofmt` from a function that also knows
gofmt's flags and its failure text. `src/gen/emit/emit.zig` spells `_gen.go`
in eleven path builders.

Nothing marks which of those are language rules, so a reader cannot tell what
a second output language would have to answer, and the answers cannot be
listed without grepping. The research in
`docs/.agent/research/rust-target-feasibility.md` names this as blocker 5 and
puts it second in the recommended order, after the IR namespacing that plan
`185-ir-target-namespacing` finished.

Afterwards there is one file to read: `src/gen/target.zig` declares what a
target must answer, and `src/gen/target/go.zig` is Go's answer. The
target-agnostic layers -- validation, reflection, the plugin contract, the
generator driver, the CLI and the build integration -- receive a `Target`
value and never name Go. Generated output does not change at all: this plan
moves rules, it does not change them.

## Measurable goals

- `src/gen/naming.zig` declares no Go-specific `pub fn`. What stays is the
  neutral string transforms (`snakeAlloc`, `pascalAlloc`, `camelAlloc`,
  `stripFunctionPrefix`), the C ABI names (`functionSymbolAlloc`,
  `legacyFunctionSymbolAlloc`, `cTypeNameAlloc`, `projectionSymbolAlloc`,
  `isCKeyword`) and the allocation helper `freeParamNames`.
- Keyword set, identifier validity, package-name validity, parameter-name
  derivation, public-name case rules, owner and variant name derivation,
  generated file naming and the formatter invocation are all reachable through
  one `Target` value.
- No file under `src/gen/validate/`, `src/reflect/`, `src/gen/generator.zig`,
  `src/gen/report.zig` or `src/main.zig` names the Go target except at the
  documented resolution points.
- `scripts/update-generator-cases.sh` leaves `tests/generator_cases` clean, and
  no `.go`, `.zig`, `.h` or `semantic.json` output changes anywhere.
- The plan records, concretely, what a Rust target would have to implement and
  what it would not have to touch.

## Supported scope and non-goals

In scope: the new `target` module and its Go implementation, the Go-specific
functions moved out of `src/gen/naming.zig` and `src/gen/ir/semantic.zig`,
their callers, the `Target` value threading through the target-agnostic layers,
the generated-file-name and formatter records, and the build wiring in
`build.zig`, `build/modules.zig` and `build/tests.zig` that the new module
needs.

Non-goals, each deliberately left alone:

- The plugin contract in `src/plugin.zig` (`writeGoType`, `GoFile`,
  `GoPackage`, `map_type`). Plan 3 in the research document owns it. Only the
  Go-rule calls inside `src/plugin/interfaces.zig` are repointed here.
- The author-facing DSL in `src/declare.zig`, `src/author.zig`, `src/root.zig`.
  Its `go:`, `go_error` and `go_name` spellings are user-visible.
- Cancellation (`context.Context`, `SemanticFn.cancel`). Research blocker 2,
  its own design problem.
- `Package` and `package`: a sub-package is a general module concept.
- The bulk `pascalAlloc` / `snakeAlloc` calls inside `src/gen/emit/**`. That
  tree is the Go target's own emitter, measured at 0% Rust reuse; it is on the
  target's side of the seam, not a caller of it. See ORDERING.
- Any Rust code.
- The `zigo` name.

## Reference source / commit / license

Branch `ir-target-namespacing` at `e5f2e28b`, which carries plan
`185-ir-target-namespacing` and is not yet on `main`. Prior art in this
repository: `src/plugin.zig`'s `Plugin` is already a record of function
pointers selected at build time, and `185-ir-target-namespacing` is the
precedent for the read-through-a-seam-first ordering used here.

## Completion criteria for the whole plan

All three phases `done`; `planr overview` reports the plan complete; root
`zig build test --summary all` passes; every example passes
`zig build test go-check go-lib abi-check go-coverage` and `go test ./...`;
`git status --short tests/generator_cases` is empty after
`scripts/update-generator-cases.sh`.
