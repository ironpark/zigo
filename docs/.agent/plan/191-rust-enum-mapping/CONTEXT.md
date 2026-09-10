# SCOPE

New Rust-only enums.zig emitting src/enum.rs; edits to emit_rust types, raw, public and emitter table. New Rust generator cases and executable regression tests. Build test wiring only as needed. No Go emitter, shim/header, semantic IR, lowering or ir_version edits.

# CONTEXT

## Current implementation and bottlenecks
reachesEnum rejects every enum boundary. Shape already separates has_status_code from declares_errors; enum payload conversion must run only after status success. C ABI always transports integers. AbiEnum has tag and constants; semantic declarations retain exhaustive/open/text and liveFields removes omitted members.

## Target structure and invariants
Closed enums use #[repr(tag)] and TryFrom<tag, Error=tag> with explicit matches, and From<Enum> for tag. Unknown or omitted returned closed tags panic as native contract defects, even on Result functions: their declared Zig error sets remain unchanged. No transmute or unchecked integer-to-enum cast.
Open enums use #[repr(transparent)] private integer storage and PascalCase associated constants (a scoped naming-lint allowance gives the same Enum::Member spelling as closed enums). TryFrom validates the Zig tag range if ABI promotion widened it; otherwise every tag is accepted. From returns the original integer. This avoids Unknown-variant collisions and invalid discriminants. Text uses original member names; unknown open values display Type(value). FromStr accepts live names only and reports a static descriptive error for other input; numeric display is diagnostic, not a promised parse roundtrip.
Use Rust's empty-initialism Pascal conversion for variants and named type spellings. Reject unrepresentable enum declarations and generated name collisions with ZIGO060 rather than emitting broken code. Omitted closed members have no public variant and fail checked conversion. Empty closed enums cannot have an integer repr and are diagnosed. Enum-containing slices remain diagnosed because casting native arrays to closed Rust enum arrays is unsound and elementwise conversion is a separate feature. Enum value receivers remain diagnosed to keep method placement out of scope.
