---
depends_on:
- "188-minimal-rust-backend#0"
perf_phase: false
status: planned
---
> DONE-WHEN: `targets.byName("rust")` returns the value and `targets.default.name` is
> NEXT: none

# Give Rust a Target value and an IR namespace

## Planned Work

- `src/gen/targets/rust_words.zig`, importing only `std`: Rust's strict and
  reserved keyword sets, `isIdentifier` (same shape as Go's minus the bare-`_`
  rejection, since `_`-leading names are ordinary in Rust), a lax
  `isConversionFunctionName` that also accepts `::` because a Rust conversion
  name is a path, and `validateCrateName` for `build.zig`.
- `src/gen/targets/rust.zig` with the `Target` value: `name` `"rust"`,
  `display_name` `"Rust"`, `source_extension` `".rs"`, `test_file_suffix` null
  (Rust tests are `#[cfg(test)]`, not a filename rule), `generated_suffix`
  empty (generated files live in their own `src/` directory, so the Go
  `_gen` stem marker earns nothing), and a `rustfmt --edition 2021` formatter
  with `--rustfmt <path>` and an "install a Rust toolchain" hint.
- Rust's naming rules: `exportedTypeNameAlloc` = Pascal with an empty
  initialism table, `exportedFunctionNameAlloc` = snake, `unexportedNameAlloc`
  = snake, `packageNameAlloc` = snake, `paramNamesAlloc` = snake with escapes
  against keywords, against the locals the generated bodies introduce (a Rust
  reserved-locals table, not Go's) and against duplicates. A name that lands on
  a keyword takes the `r#` raw-identifier escape where that is legal and a
  trailing `_` where it is not; record which choice was made and why.
- A `rust` namespace in `src/gen/ir/semantic.zig`: `FnRust { name }` and
  `SemanticFn.rustName()`/`setRustName()`, shaped exactly like `FnGo`/`goName`
  with the same `compact()` discipline, plus the `rust: ?FnRust = null` field.
  No `ir_version` bump and no migration -- an absent namespace serializes to
  nothing.
- Judge during implementation whether to wire `.rust` through `src/declare.zig`
  and `src/normalize.zig` so a binding can actually set the override. If the
  wiring is more than incidental, leave the IR field readable-only and record
  that decision instead of half-doing it.
- Register Rust in `targets.all`; leave `targets.default` as Go.
- Unit tests: keyword and identifier boundaries, snake/Pascal splits including
  the `Id`/`Url`/`Utf8` difference from Go, parameter escaping, and
  `byName("rust")`.

## Done When

- `targets.byName("rust")` returns the value and `targets.default.name` is
  still `"go"`.
- `src/gen/targets/rust_words.zig` imports only `std` -- verifiable by grep and
  by `build.zig` importing it.
- A test asserts Rust and Go disagree on `lookupID` (`lookup_id` vs `LookupID`)
  and on the Pascal spelling of a `Url`-bearing name.
- Round-tripping a `semantic.json` that carries no `rust` key produces no
  `rust` key, and one that carries `{"rust":{"name":"..."}}` reads back through
  `rustName()`.
- `zig build test --summary all` green.
- `scripts/update-generator-cases.sh` then
  `git status --short tests/generator_cases` empty -- the new namespace and the
  new target must be invisible to Go generation.
- Thirteen examples green as in phase 0; `git status --short examples` empty.
- `zig fmt --check src build build.zig` clean. Committed.
