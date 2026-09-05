# GOALS

## Problem and the end result from the user's point of view

`src/gen/emit.zig` (10,700 lines), `src/gen/validate.zig` (4,800 lines) and
`build.zig` (2,000 lines) each hold several concerns in one file, and the same
facts about a function (does it get a `Must` variant, is a helper referenced,
which materialized layout does it return) are computed in two or three places.
The `/simplify` pass on 0.7.4..0.8.1 found most duplication came from that one
cause. After this plan the generator is organized by output file, every shared
decision is made once in lowering and read by emit and validate, and a consumer
reading `build.zig` sees only the `addGoBindings` API. Generated output stays
byte-for-byte identical; this is a restructure, not a feature.

## Measurable goals

- No source file under `src/gen` exceeds 3,000 lines; `build.zig` stays under 1,000.
- Every golden case under `tests/generator_cases` is unchanged.
- The Must-variant rule and the helper-reference rule each have exactly one definition.
- `zig build test` passes after every phase.

## Supported scope and non-goals

Go remains the only target language. No new binding features, no CLI changes,
no change to `semantic.json` or the C ABI. A second target language is
explicitly out of scope; the split is by concern, not by an abstract backend
interface.

## Reference source / commit / license

Baseline is commit `f9f3225` (Consolidate duplicated predicates across gen and
reflect). No external sources.

## Completion criteria for the whole plan

All phases done, `zig build test` green, goldens unchanged, and `docs/development.md`
describes the new file layout.
