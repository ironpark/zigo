---
completed_at: "2026-09-06T14:18:27Z"
depends_on:
- "135-value-receivers-for-enums#0"
perf_phase: false
status: done
---
> DONE-WHEN: Each rejection has a case with the declaration site in the message, and the
> NEXT: none

# Reject what a value receiver cannot mean

## Planned Work

- New diagnostic for ownership and lifetime metadata on a value receiver:
  `constructs`, `destroys`, `child_of_receiver`, `.returns = .borrowed`,
  `.iterator`, `io` stream parameters, and membership in an `interfaces` entry.
- New diagnostic for a receiver whose registered entry carries a `.go` adapter
  (Go cannot define a method on a non-local type), and for a `.repr = .value`
  receiver, pointing at the out-of-scope note so the message is actionable.
- Extend the per-receiver name check in `validate/names.zig` to reserve the
  methods zigo itself generates on an enum: `String`, and with `.text = true`,
  `MarshalText` and `UnmarshalText`.
- Document the new codes in `docs/diagnostics.md` with cause and fix.

## Done When

- Each rejection has a case with the declaration site in the message, and the
  reserved-name check fires for a Zig `Key.string` against the generated
  `String()`.
