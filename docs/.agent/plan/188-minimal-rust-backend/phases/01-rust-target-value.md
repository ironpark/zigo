---
completed_at: "2026-09-10T04:18:28Z"
depends_on:
- "188-minimal-rust-backend#0"
perf_phase: false
status: done
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
  and `src/normalize.zig` so a binding can actually set the override.
  **Outcome: not wired, and the reason is a finding rather than a shortcut.**
  Tracing the Go side showed that a binding's `.name = "..."` on a function
  does *not* reach `FnGo.name` at all -- `src/reflect/walk.zig:825` puts it in
  `SemanticFn.name` and records the Zig declaration in `zig_path`. The only
  writer of `FnGo.name` is `src/gen/validate/validate.zig:218`, which calls
  `function.setGoName(name)` for a plugin's `name_function` hook. So there is
  nothing in the declaration DSL to mirror: the sibling of that call site is a
  plugin, and a plugin's `output_targets` defaults to `&.{"go"}` (plan 187), so
  no plugin runs for a Rust target in the first place.
  `rustName()` is therefore readable and unreachable in the minimal backend,
  which is correct: the seam asks a target for `nameOverride` and Rust answers
  it, with the right shape, from its own namespace.
  **The creak to hand on:** `validate.zig:218` hardcodes `setGoName` where it
  should route through the resolved target. `Target` has no name-override
  *setter* -- only a getter -- so a plugin that renames functions for a
  non-Go target would need one added. Left alone deliberately: this plan's
  acceptance says no `src/gen/validate/**` caller is edited to accommodate
  Rust, and none is, because no Rust plugin exists to need it.
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
