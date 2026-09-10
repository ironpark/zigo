---
depends_on:
- "188-minimal-rust-backend#1"
perf_phase: false
status: in-progress
---
> DONE-WHEN: `src/gen/emit/emit.zig` defines `core_emitters` as
> NEXT: none

# Name the neutral emitters and write the Rust emitter

## Planned Work

- In `src/gen/emit/emit.zig`, split `core_emitters` into `neutral_emitters`
  (shim, panic source, header) and `go_emitters` (raw, both purego loaders,
  lifecycle), and define `core_emitters = neutral_emitters ++ go_emitters` so
  the order and therefore every manifest is unchanged.
- New `src/gen/emit_rust/`:
  - `emit.zig` -- the emitter table: `neutral_emitters` plus Rust's own, and
    the path rules for `src/raw.rs` and `src/lib.rs`.
  - `types.zig` -- `AbiScalar` and the supported `AbiParam.Role` set spelled as
    Rust types, for the raw layer and the public layer respectively. An
    unsupported shape must produce a diagnostic naming the shape and the
    function, not a silently wrong signature or a crash.
  - `raw.zig` -- the `extern "C"` block over the C header's symbols, plus one
    `unsafe` wrapper per function that marshals slices to `(ptr, len)` and
    error unions to `(payload, code)`.
  - `public.zig` -- safe wrappers: `&[T]`/`&str` parameters, `Result<T, Error>`
    returns, doc comments carried from the IR, and the error enum built from
    `errors.lock.json` codes including the reserved negative codes and the
    `<= -256` native-panic range.
- In `src/gen/generator.zig`, choose the emitter table from
  `options.output_target`. Keep the choice to one place, and keep the Go path's
  behaviour identical -- including the `.go` trailing-newline normalization in
  `appendEmitters`, which must become a question about the target's source
  extension rather than a literal `".go"` if Rust needs the same treatment.
- Teach `tests/generator_case_main.zig` an `output_target` option defaulting to
  `"go"`, and add Rust cases: `rust_scalar`, `rust_slice`, `rust_errors`, each
  reusing an existing case's `semantic.json` shape so the input is known-good.
  Register their `expected` directories in `build/tests.zig`.
- Verify the emitted Rust is real Rust, not just plausible text: compile each
  new golden with `rustc --edition 2021 --crate-type lib` in a test or a script
  step. Text that no compiler has seen is the failure mode this phase exists to
  avoid.

## Done When

- `src/gen/emit/emit.zig` defines `core_emitters` as
  `neutral_emitters ++ go_emitters` and no other emit file is edited:
  `git diff --stat src/gen/emit` shows one file.
- `grep -rn "\"go\"\|Go\b" src/gen/emit_rust` finds nothing but the shared
  `Emitter`/`Options` import lines, and `grep -rn "rust" src/gen/emit` finds
  nothing.
- The three Rust golden trees are committed and contain `src/raw.rs`,
  `src/lib.rs`, `shim.zig`, `panic.c` and the header, with the shim, panic
  source and header byte-identical to the corresponding Go case's.
- Each golden `src/lib.rs` and `src/raw.rs` compiles under
  `rustc --edition 2021 --crate-type lib`.
- `scripts/update-generator-cases.sh` then
  `git status --short tests/generator_cases` empty, now over 77 cases.
- `zig build test --summary all` green; thirteen examples green;
  `git status --short examples` empty; `zig fmt --check` clean. Committed.
