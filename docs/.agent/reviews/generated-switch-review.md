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
