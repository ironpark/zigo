---
depends_on:
- "191-rust-enum-mapping#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: All acceptance checks pass, Go output remains unchanged, actual cargo test/demo and before/after audit evidence recorded.
> NEXT: none

# Verify the repository and document the mapping

## Planned Work

- Run all 13 Go example build steps and go tests, and all Rust example build/cargo checks and demo for real.
- Repeat root tests, full generator regeneration, fresh audit and format checks; record counts and unchanged output evidence.
- Update Unreleased changelog and research next-person list with enum design, actual reuse/new line counts, results, remaining enum slices/receivers and other handoffs. Record any divergence using planr edit.

## Done When

- All acceptance checks pass, Go output remains unchanged, actual cargo test/demo and before/after audit evidence recorded.
- Documentation committed and both phases marked done with clean working tree.

## Outcome

- All 13 Go examples (00 through 12) passed zig build test go-check go-lib abi-check go-coverage --summary all and go test ./.... Rust example 13 passed zig build test rust-check rust-lib abi-check rust-coverage --summary all, cargo fmt --check, cargo clippy --all-targets -- -D warnings, cargo test and cargo run --example demo. All commands actually ran; existing macOS linker version warnings were unchanged.
- Root verification again passed 434/434 steps and 672/672 Zig tests, plus the Rust runtime executable with 7/7 tests. New golden crates also passed rustfmt and clippy with warnings denied using temporary Cargo manifests pointing their lib target at expected/src/lib.rs and test target at runtime.rs. The root build permanently compiles/runs runtime.rs with rustc --test -D warnings.
- Full regeneration after the implementation commit: git status --short tests/generator_cases is empty. Actual document count is 85 (74 Go + 11 Rust), with 83 at the branch base. The 74 existing Go trees have no diff against 4c6db7a6.
- git diff 4c6db7a6 -- examples is empty, stronger than the requested .go/.h/shim.zig/panic.c/semantic.json comparison. No shared Go emitter, shim/header, IR or lowering source changed. zig fmt --check src build build.zig and git diff --check are clean.
- Final fresh zig-out/bin/zigo-gen audit on the 74 non-Rust documents: before accepted=7 broken= crashed=; after accepted=10 broken= crashed=. New acceptances: enum_text, enum_lookup, enum_lookup_purego; remaining 64 are diagnostics.
- Added enums.zig: 213 lines, including declaration diagnostics and unit tests. Existing Rust emitter diff: +75/-24; total emit_rust grew 2096 to 2360 lines. Reused without edits: reflect 8620, IR 3049, lowering 3292, validation 6416, shim/header/target_types 1887 lines. Runtime test wiring adds 22 lines; runtime.rs is 148 lines containing 7 tests.
- Existing refs stayed main=c92ec348, rust-minimal-backend=7cdf8e7f, rust-handles-and-buffers=4c6db7a6. No push, PR, merge, rebase or reset.

Actual Rust example output:

```text
test result: ok. 9 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out

2 + 3 = 5
sum([1, 2, 3]) = 6
7 / 2 = 3
1 / 0 failed: zigo: divide: DivideByZero
tally.add(40) = 40
tally.add(2) = 42
tally.peek() = 42
reading.total() = 42
tally.render() = total=42
live bytes after drop = 0
```

## Handoff and scope

Open scalar enums are fully supported through checked transparent newtypes, including unknown values and promoted tag widths. Closed enums never receive unchecked discriminants. Text parses only live Zig member names; the numeric open-enum display is diagnostic and deliberately not a parse roundtrip. Enum receivers and enum slice/buffer/optional shapes stay ZIGO060 and need method placement or elementwise validity/ownership design. Namespaces, tagged unions, Rust plugins, dependent handles and cancellation remain separate work.

## Divergence

The only existing golden changes are one redundant blank line removed from three Rust handle raw.rs files, discovered by the new handle+enum rustfmt check. Raw enum-input wrappers also needed an explicit unsafe validity contract. Both changes were incorporated with planr edit during phase 0. No open-enum support was dropped.
