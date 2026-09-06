---
depends_on:
- "135-value-receivers-for-enums#2"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Docs describe the supported shape and every rejection, and the changelog says
> NEXT: none

# Document and land

## Planned Work

- `docs/bindings-functions.md`: enum receivers in the receiver section, with the
  value-receiver restrictions and the pointer to the diagnostics.
- `docs/bindings-types.md`: note on the enum entry that it can own methods and
  that a `.go` adapter forecloses that.
- `docs/cheatsheet.md`: `receiver` row and the `types` table mention enums; add
  the new codes to the diagnostics table.
- `CHANGELOG.md` under Unreleased: added, with the ABI note for anyone moving an
  existing wrapper under a receiver.

## Done When

- Docs describe the supported shape and every rejection, and the changelog says
  the move is breaking for existing bindings that adopt it.
