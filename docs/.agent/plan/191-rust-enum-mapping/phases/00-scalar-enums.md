---
completed_at: "2026-09-10T07:09:56Z"
perf_phase: false
status: done
---
> DONE-WHEN: Root zig build test passes, new goldens compile with edition 2021 -D warnings, rustfmt and clippy pass, executable boundary tests pass.
> NEXT: none

# Map scalar enums safely

## Planned Work

- Add conditional enum module with closed/open representations, checked conversions and optional text traits.
- Replace scalar boundary refusal with named public spelling and integer marshalling, including status payloads and handle methods; retain precise unsupported-shape diagnostics.
- Add goldens covering signed/unsigned widths, open unknown tags, omitted fields, text, naming, direct and error payloads. Update obsolete refusal test and add edge diagnostics.
- Add executable Rust tests against generated code with native stubs to prove actual boundary behavior, including failed status before enum conversion and invalid closed tag panic.

## Done When

- Root zig build test passes, new goldens compile with edition 2021 -D warnings, rustfmt and clippy pass, executable boundary tests pass.
- All generator cases regenerate with no existing Go output drift (existing Rust handle raw files lose one redundant blank line); fresh audit reports zero broken/crashed. Zig fmt clean. Implementation and evidence committed before phase done.

## Divergence

- Rustfmt of the new handle+enum case exposed a pre-existing extra blank line before the first opaque declaration in raw.rs. Fix it in the Rust emitter and regenerate the affected existing Rust goldens; only that whitespace changes there. Existing Go output remains byte-identical.
- Raw wrappers with integer enum inputs must be unsafe: only the named public type guarantees validity in Zig, particularly for closed enums and promoted narrow tags. This safety requirement was not explicit in the initial plan.

## Outcome

- Root: 434/434 build steps, 672/672 Zig tests; the separate Rust boundary executable runs 7/7 tests. Both new golden crates pass cargo fmt --check and cargo clippy --all-targets -- -D warnings, and cargo test.
- Full regeneration covers 85 documents (74 Go, 11 Rust), not the briefing count of 79: the branch base already had 83. All 74 existing Go trees are byte-identical. Existing Rust raw.rs goldens rust_borrowed_view, rust_handle, rust_handle_buffer each lose exactly one extra blank line.
- Fresh installed-generator audit: before accepted=7 broken= crashed=; after accepted=10 broken= crashed=. Newly accepted: enum_text, enum_lookup, enum_lookup_purego. The other 64 documents produce diagnostics, never crashes.
- zig fmt --check src build build.zig and git diff --check pass. No shared IR, Go emitter, lowering, shim or header source was edited.
- Empty open enums need direct Display/FromStr bodies rather than single-arm matches: clippy caught this and the golden now covers it.
