# SCOPE

- Purely additive Go surface behind an option.

# CONTEXT

## Current implementation and bottlenecks

- `Must*` exists only for union projections/snapshots.

## Target structure and invariants

- One renderer emits `Must*` from the same signature data as the public function, so the two cannot drift.
