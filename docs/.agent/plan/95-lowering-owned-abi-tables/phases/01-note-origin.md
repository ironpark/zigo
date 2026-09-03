---
perf_phase: false
status: planned
---
> DONE-WHEN: `validate.zig` snapshot tests unchanged and green.
> NEXT: none

# Identifier note origin

## Planned Work

- Replace `note` + `type_note` with a tagged union in `CIdentifierOrigin`; update the six call sites and any helper; diagnostics snapshots must stay identical.

## Done When

- `validate.zig` snapshot tests unchanged and green.
