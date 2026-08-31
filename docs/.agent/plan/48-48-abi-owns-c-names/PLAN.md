---
description: Move C type-name minting out of the emitter into lowering, and expose lowered struct records on AbiFn/AbiParam
plan_status: in-progress
registered_at: "2026-08-31T18:08:46Z"
---
> NEXT: Add the `AbiEnum`, `AbiOpaque`, and `AbiScalar.opaque` C-name records to the IR and populate them in lowering. ([Phase 0](phases/00-ir-enum-opaque-names.md))

# Phases

- [ ] [Phase 00: IR records for enums and handles](phases/00-ir-enum-opaque-names.md)
- [ ] [Phase 01: Emitter reads C names from the IR](phases/01-emit-consumes-c-names.md)
- [ ] [Phase 02: Functions carry their own struct records](phases/02-fn-struct-records.md)

# Shared Verification

- `zig build test` — unit and snapshot harness.
- `zig build check` — every artifact compiles.
- The generated-artifact snapshot comparison must pass with no update applied.
  A snapshot diff in any phase means the refactor changed behaviour and is
  wrong, since none of the three phases is meant to alter output.

# Decisions That Constrain Ordering

Phase 0 adds IR without any consumer, so it can land and be tested on its own.
Phase 1 removes the emitter's duplicate naming and is the plan's actual point.
Phase 2 is independent of naming and could be done first, but it is ordered
last so that a snapshot diff during phase 1 is unambiguously about naming.

# Next Implementation Target

Add the `AbiEnum`, `AbiOpaque`, and `AbiScalar.opaque` C-name records to the IR and populate them in lowering.
