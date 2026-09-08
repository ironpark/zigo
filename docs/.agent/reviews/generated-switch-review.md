# Generated switch lookup review

Scope: inspection only; generator behavior is unchanged.

| Emitter | Candidate | Recommendation |
| --- | --- | --- |
| src/gen/emit/public_types.zig:903 | Enum String | First candidate: bounded fixed string array for dense values, with lower/upper bounds and an offset for negative minima. Sparse or excessively wide domains retain switch until measured. |
| plugins/enumkit/src/plugin.zig:41 | IsKnown | Contiguous exported values need only a range check; holes require presence information. Consider sharing enum lookup metadata instead of emitting another switch. |
| src/gen/emit/public_types.zig:958 | ParseEnum | Candidate for a private string-to-enum map for large enums; compare against switch before selecting a threshold. |
| plugins/json/src/plugin.zig:68 | UnmarshalJSON | Candidate for sharing the named-value reverse lookup with text parsing. Preserve JSON rejection of unknown names: delegating directly to open-enum Parse changes accepted input. |
| src/gen/emit/public_types.zig:1067 | zigoErrorForCode | Separate code-to-name lookup from the common Error allocation. Bounded dense codes can use an array; sparse codes require a fallback. Preserve panic handling, special codes, unknown formatting, and per-call Operation. |

Keep union conversion and variant dispatch switches (public_types.zig:296,635,657): each branch performs type-specific work. Projection error dispatch at line 744 has just one special case and constructs different error types; a lookup table adds little structural benefit.

Existing enum_text fixtures contain both unsigned open enums and signed values -1,0,1. Use liveFields, preserving excluded tags and declaration order for Values. Range calculations must handle full-width signed/unsigned values without subtraction overflow; guard before converting to an array index. An empty string cannot be used as a missing-entry sentinel unless empty tag names are prohibited; otherwise use explicit presence metadata.

ErrorsLock assigns positive codes sequentially but accepts validated persisted mappings: do not assume every input has a compact code range. Bound array size independently of density. Do not reuse mutable exported Err pointers for operation-specific returned errors.

Before implementation: benchmark representative small/large, dense/sparse enums with named and unknown hits, plus negative and wide numeric domains. Compare lookup time, allocations, generated size, binary size, and map initialization cost. This review establishes candidates, not measured performance improvements. Validate generated behavior through snapshots and Go tests for both backends after implementation.

## Implemented

Dense enum String methods and positive error code lookup now use private fixed-size name arrays. The generator caps arrays at 4,096 slots and requires at least 50% occupancy; singletons, empty enums, wide/sparse domains, and enums containing an empty tag name retain switch generation. Signed array indices use guarded unsigned arithmetic, including the minimum i64 value. Contiguous enum arrays return directly; arrays with holes check the missing-name marker. Enumkit emits a range check when all exported values are contiguous, preserving its switch for holes.

Text and JSON parsing retain their switches. Union dispatch remains unchanged. Unknown enum/error formatting, JSON acceptance rules, per-operation Error allocation, panic handling, and exported sentinel identity are preserved.

Validation: `zig build test --summary all` passed 332/332 steps and 798/798 tests. All example bindings were regenerated, including both available backends. Tagged-union cgo/purego and event-queue Go tests passed. Boundary fixtures execute generated enum code for both backends; error tests cover operation context, identity, unknown codes, and native panic dispatch. Emitter tests cover sparse persisted error codes and array holes.

Run `zig build lookup-bench` for repeatable comparisons against switch baselines. Representative measurements on Apple M1 Ultra, darwin/arm64, Go 1.27.1 (three runs, 300 ms each):

| Lookup | Array | Switch | Map |
| --- | --- | --- | --- |
| Four named enum values | 2.27–2.34 ns/op | 2.19–2.21 ns/op | — |
| 32 named enum values | 2.20–2.22 ns/op | 2.20 ns/op | — |
| Unknown value in 32-tag enum | 27.2–27.3 ns/op | 27.5–28.9 ns/op | — |
| Four enum names parsed | — | 2.33–2.42 ns/op | 8.05–8.06 ns/op |
| Five error codes | 15.9–16.4 ns/op | 16.0–16.8 ns/op | — |

These measurements do not establish a general speedup: named lookups are effectively comparable, with a small four-tag regression on this machine. The benefit is explicit bounded lookup data and less repeated branching/allocation code in generated source. Known enum lookups allocate nothing; unknown enum formatting retains one allocation and error construction retains one 48-byte allocation. The compiler emitted equal-sized 160-byte function bodies for the 32-tag array and switch benchmarks, so no binary-size reduction is claimed. Map adoption for larger enums would require separate measurements; this change does not infer a universal crossover threshold.
