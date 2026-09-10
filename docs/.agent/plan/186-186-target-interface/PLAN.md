---
completed_at: "2026-09-10T03:20:29Z"
description: Extract a Target interface so the output language's keyword, naming, layout and formatter rules live in one place
plan_status: done
registered_at: "2026-09-10T02:48:46Z"
---
> NEXT: None. All three phases are done; the hand-offs are listed under `What a Rust Target Implements`.

# Phases

- [x] [Phase 00: Introduce the Target seam with Go behind it](phases/00-introduce-target-seam.md)
- [x] [Phase 01: Thread the target as a value](phases/01-thread-target-value.md)
- [x] [Phase 02: Move file layout and the formatter behind the target](phases/02-layout-and-formatter.md)

# Shared Verification

- `zig build test --summary all` at the repository root, every phase. The root
  build has no `go-check`, `abi-check` or `go-coverage` step -- those are
  defined in each example's build, so the fuller run is per example:
  `cd examples/<name> && zig build test go-check go-lib abi-check go-coverage`
  then `(cd go && go test ./...)`, over all thirteen.
- `scripts/update-generator-cases.sh` followed by
  `git status --short tests/generator_cases`, which must be empty, every phase.
  The 74 cases regenerate the whole Go, shim and header surface from checked-in
  documents, so an empty diff is the plan's central pass criterion: a rule that
  changed while moving, or a caller left on a deleted path with a subtly
  different fallback, shows up as a moved golden file.
- `git status --short` over `examples/*/zigo` and `examples/*/go` after the
  example runs, which must also be empty: `go-check` regenerates into the
  committed tree, so any drift in `semantic.json` or generated Go appears there.
- `git diff --stat` at the end of each phase must show no generated artifact.
- The `grep` assertions in each phase's Done When, which are what turn "the
  rules are gathered" from a claim into a check.

# What a Rust Target Implements

The point of the plan, stated as a checklist. Adding Rust means writing
`src/gen/targets/rust.zig` with a `Target` value, plus a `rust_words.zig` leaf
if the build integration has to validate crate names. It means editing no
caller in `src/gen/validate/**`, `src/gen/report.zig`, `src/gen/abi_diff.zig`,
`src/gen/generator.zig` or `src/reflect/**`.

| `Target` member | Go | What Rust answers |
|---|---|---|
| `name` | `"go"` | `"rust"` |
| `display_name` | `"Go"` | `"Rust"` |
| `source_extension` | `".go"` | `".rs"` |
| `generated_suffix` | `"_gen"` | `"_gen"`, or empty with generated files in their own module directory |
| `formatter` | `gofmt -w`, `--gofmt <path>` | `rustfmt --edition 2021`, `--rustfmt <path>`, "install a Rust toolchain" |
| `isKeyword` | 25 Go keywords | Rust's strict and reserved keywords, and the `r#` raw-identifier escape is available where Go has only `_` suffixing |
| `isIdentifier` | ASCII, no keyword, no bare `_` | same shape; `_`-leading names are ordinary in Rust, so the bare-`_` rejection would go |
| `isConversionFunctionName` | lax: any alphanumeric/`_` run | a path, so this would have to accept `::` or stay lax |
| `paramNamesAlloc` | camelCase, escape keyword/local/duplicate | snake_case, same three escapes, a different reserved-locals table |
| `exportedNameAlloc` | `pascalAlloc` | `pascalAlloc` for types, `snakeAlloc` for functions -- so a Rust target splits this into a type rule and a function rule, the one interface change adding Rust would ask for |
| `unexportedNameAlloc` | `camelAlloc` | `snakeAlloc` |
| `packageNameAlloc` | `snakeAlloc` | `snakeAlloc` |
| `nameOverride` | `SemanticFn.goName()` | `SemanticFn.rustName()`, a sibling namespace beside the `go` one plan 185 created |
| `libraryPathEnvironmentAlloc` | `ZIGO_<PKG>_LIBRARY_PATH` | the same, reused as is |
| `publicFunctionNameAlloc` | provided by `Target` | provided by `Target`; it composes the three members above and needs no reimplementation |

Not behind the seam, and each its own plan:

- **The plugin contract.** `writeGoType`, `GoFile`, `GoPackage`,
  `plugin.GoFileKind` and `Context.goFilePathAlloc` are Go-typed, so the
  `ZIGO059` output-path rule in `src/gen/generator.zig` and the interface-name
  check in `src/plugin/interfaces.zig` stay on `targets.default`. This is
  step 3 of the research document's recommended order.
- **`src/gen/sync_check.zig`.** Its `.go` filter decides which files in a
  published tree are compared. It has no options record to carry a target, and
  `zigo check` is a tooling entry point rather than a generation one.
- **The `--gofmt` flag and `zigo doctor`.** Both are user-visible tooling
  surface (research blocker 4). The flag keeps its name; only what it feeds
  moved. `cli.Doctor.gofmt_executable` still names Go because doctor probes the
  Go toolchain specifically.
- **The Go initialism table** inside `naming.pascalAlloc` and
  `naming.camelAlloc` (`id` -> `ID`, `url` -> `URL`, `utf8` -> `UTF8`). That is
  a Go style convention living in a transform this plan calls neutral. Rust
  would want `Id`, `Url`, `Utf8`. Parameterizing it means touching 59
  `pascalAlloc` call sites, so it is deliberately left for the plan that adds
  the second target, where the change has a reason to exist.
- **Cancellation.** `context.Context`, `SemanticFn.cancel` and `cancel_error`.
  Research blocker 2.

# Decisions That Constrain Ordering

The seam comes before the threading, for the reason plan 185 proved: moving
rules while every caller still resolves the target locally is verifiable with
zero snapshot churn, so a green phase 0 is evidence that the caller set is
complete. Threading then has a known set of signatures to change instead of a
search, and any failure in phase 1 is a compile error rather than a silent
change of behaviour.

`src/gen/emit/**` stays on the target's side of the seam throughout. The whole
tree exists to write Go, was measured at 0% reuse for a second language, and
would be replaced wholesale by a Rust emitter rather than parameterized. Making
its 59 `pascalAlloc` calls go through a `Target` would enlarge the diff by an
order of magnitude and would say something false: that a Rust backend reuses
those code paths. The seam is placed where reuse actually stops.

File layout and the formatter come last because they are the only parts that
touch the output tree's shape and the process the CLI runs. Keeping them in
their own phase means that if a golden file does move, the phase boundary says
whether a naming rule or a layout rule moved it.

Phase 0 leaves no intermediate document shape: nothing in this plan changes
`semantic.json`, so unlike plan 185 the phase boundaries cannot produce a
document that a later commit fails to parse. `abi-check` reading
`git show <ref>:zigo/semantic.json` therefore stays valid at every commit.

# Next Implementation Target

None. All three phases are done; the hand-offs are listed under
`What a Rust Target Implements`.
