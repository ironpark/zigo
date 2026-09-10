# SCOPE

Files this plan expects to touch.

New:

- `src/gen/targets/rust_words.zig` -- Rust's word-level rules, `std` only.
- `src/gen/targets/rust.zig` -- the `Target` value and Rust's naming rules.
- `src/gen/emit_rust/*.zig` -- the Rust emitter: raw `extern "C"` bindings, the
  safe public wrapper, the error enum, and the emitter table.
- `tests/generator_cases/rust_*/` -- Rust goldens.
- `examples/13-rust-quick-start/` -- the runnable mirror.

Edited:

- `src/gen/targets.zig` -- split the exported-name rule; register Rust.
- `src/gen/naming.zig` -- parameterize the initialism table (see CONTEXT).
- `src/gen/ir/semantic.zig` -- a `rust` namespace beside `go`.
- `src/gen/emit/emit.zig` -- name which three of `core_emitters` are neutral.
- `src/gen/generator.zig` -- dispatch the emitter table on the target.
- `src/gen/cli.zig`, `src/main.zig` -- `--target`.
- `build.zig`, `build/tests.zig` -- Rust build integration and new cases.
- `CHANGELOG.md`, `docs/.agent/research/rust-target-feasibility.md`.

Explicitly not edited: `src/gen/emit/{public,public_types,public_runtime,raw,purego,callbacks,handles,materialized*,stream*}.zig`, any validator, `src/gen/report.zig`, `src/gen/abi_diff.zig`, `src/reflect/**`, `plugins/**`.

# CONTEXT

## Current implementation and bottlenecks

The pipeline pivots on the C ABI shim. `Zig -> semantic IR -> shim + C header`
knows no output language. `src/gen/emit/**` (about 11K lines) is Go's emitter
and sits behind the `targets.Target` seam on purpose. validate, reflect,
`abi_diff`, report and the generator driver all take a `Target` by value.

Four concrete obstacles, measured rather than guessed:

**1. `exportedNameAlloc` conflates two rules.** Go answers `pascalAlloc` for
both a type name and a function name because Go spells them the same way. Rust
does not: types are `PascalCase`, functions are `snake_case`. Plan 186 wrote
this down as "the one interface change adding Rust would ask for". The blast
radius is small: `grep` finds `exportedNameAlloc` called from exactly one place
outside the target files, `Target.publicFunctionNameAlloc` in
`src/gen/targets.zig`. `unexportedNameAlloc` has no callers at all today.

**2. The Go initialism table is inside a transform called neutral.**
`naming.pascalAlloc` and `naming.camelAlloc` map `id` -> `ID`, `url` -> `URL`,
`utf8` -> `UTF8`. Rust wants `Id`, `Url`, `Utf8`. Plan 186 deferred this
because parameterizing it looked like touching 59 `pascalAlloc` call sites.

That estimate was for making the *call sites* go through a `Target`. This plan
does something smaller and does not defer: `pascalAlloc(a, input)` keeps its
signature and becomes a one-line wrapper over
`pascalWithInitialismsAlloc(a, input, go_initialisms)`. Rust's type rule calls
the same helper with an empty table. Zero call sites move, Go's bytes cannot
change, and Rust gets the spelling it wants. The Go table stays in `naming.zig`
rather than moving to `targets/go.zig` because `camelAlloc` shares it and
`naming.zig` is a leaf both targets already depend on.

Where this actually bites in the minimum: only error-variant names, since the
minimal backend binds free functions (snake_case, no table) and has no types.
An error named `InvalidURL` would otherwise reach Rust as `InvalidURL` instead
of `InvalidUrl`. Small, but it is the one place the minimum touches the Pascal
path, so it is worth having correct rather than noted.

**3. `emit.core_emitters` mixes neutral and Go-only entries.** The array is
shim, panic source, header (all neutral), then raw, two purego loaders and
lifecycle (all Go). A Rust backend needs the first three and none of the last
four.

This plan splits the array into `neutral_emitters ++ go_emitters` and leaves
`core_emitters` defined as exactly that concatenation. The order is preserved,
so `.zigo-outputs.json` and every golden manifest are byte-identical. This is
the one edit inside `src/gen/emit/**`, and it is a renaming rather than a
generalization: it labels which three entries were already language-neutral. It
does not make any Go emitter reachable from Rust.

**4. Build integration is 480 lines of `addGoBindings`.** Most of it is cgo:
`#cgo` flag composition, `go.mod` management, purego loading policy, Go
platform words. The reflector module graph and the semantic-JSON capture at the
top, though, are language-neutral -- research measured `src/reflect/` at
"almost 100%" reuse. Rather than parameterizing `addGoBindings` (which is
user-visible and Go-named), this plan adds a separate `addRustBindings` and
extracts the shared reflector/module setup into a helper in
`build/modules.zig`, so the two do not carry two copies of the module graph.
That is a Go-side edit; the rationale is that reflection is the layer the
research document measures as fully shared, so a single definition is the
honest arrangement, and it is behaviour-preserving for Go by construction.

`build.zig` cannot import anything that imports `semantic`, which is why
`go_words.zig` exists as a `std`-only leaf. `rust_words.zig` mirrors it, so
crate-name validation is available at build-configuration time.

## Target structure and invariants

Invariants that hold at every commit:

- **The C ABI shim, the panic source and the C header are shared verbatim.** If
  a target concept appears in `emit/shim.zig` or `emit/header.zig`, the design
  is wrong. Neither file is edited by this plan.
- **Go's generated bytes never change.** Enforced by the 74 generator cases and
  by the thirteen examples' committed trees, checked every phase.
- **The IR does not know about output languages.** Rust-specific facts go in a
  `rust` namespace beside `go` on the same declaration records, not into
  Go-named fields.
- **No `ir_version` bump and no migration.** This plan only *adds* optional
  namespace fields. `Semantic` serializes with
  `emit_null_optional_fields = false`, so an absent `rust` namespace writes
  nothing and every existing document is byte-identical. This matters because
  `abi-check` reads its baseline with `git show <ref>:zigo/semantic.json`: plan
  185 broke exactly here by version-gating a migration, so this plan avoids
  needing one at all. Any phase that finds itself wanting a key *moved* must
  stop and re-plan.
- **`src/gen/emit/**` gains no Rust knowledge and `src/gen/emit_rust/**` gains
  no Go knowledge.** They meet only at `neutral_emitters`, `Emitter`, `Options`
  and the `abi.Program` they both read.

The Rust output tree, mirroring what the Go tree does:

```
<output>/shim.zig            shared, unchanged
<output>/panic.c             shared, unchanged
<output>/zigo_<pkg>.h        shared, unchanged
<output>/src/raw.rs          extern "C" declarations + unsafe call wrappers
<output>/src/lib.rs          safe public functions, the error enum, re-exports
<output>/errors.lock.json    shared mechanism, unchanged
<output>/.zigo-outputs.json  manifest; `.rs` files carry kind `go`
<output>/Cargo.toml          hand-written by the user, like go.mod
<output>/build.rs            hand-written by the user; links the static archive
```

`.rs` files are recorded with manifest kind `go` because that tag already means
"framed source in the output language" and the manifest is a wire format --
`src/main.zig` says so where it formats. `sync_check.compare` drives off the
manifest by path, so `rust-check` works; only its no-manifest fallback walk is
`.go`-only, and a generated tree always has a manifest.

Type mapping for the supported shapes:

| Zig | C ABI | Rust raw | Rust public |
|---|---|---|---|
| `i32`, `u64`, `f64`, `bool` | same | `i32`, `u64`, `f64`, `bool` | same |
| `usize`/`isize` | `size_t`/`ptrdiff_t` | `usize`/`isize` | same |
| `[]const T` param | `const T *ptr, size_t len` | `*const T, usize` | `&[T]` |
| `[]const u8` param, utf8 | `const uint8_t *, size_t` | `*const u8, usize` | `&str` |
| `E!T` return | `int32_t` code + out param | `(T, i32)` | `Result<T, Error>` |
| `void` return | `void` | `()` | `()` |
