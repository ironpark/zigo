---
completed_at: "2026-09-07T13:49:42Z"
depends_on:
- "156-binding-authoring-polish#0"
perf_phase: false
status: done
---
> DONE-WHEN: Callback conventions match function indices and existing callback behavior is preserved in tests/examples.
> NEXT: none

# Sparse callback contracts

## Planned Work

- Share callback native-to-logical layout between normalization and reflection.
- Normalize sparse original-index callback metadata; reject duplicate, out-of-range, userdata and folded-length annotations.
- Rename public callback failure option to on_failure and migrate consumers.

## Done When

- Callback conventions match function indices and existing callback behavior is preserved in tests/examples.

## Implementation and Verification

- CallbackParam now carries an original native index; CallbackOptions uses on_failure.
- Author normalization and reflection share one callback layout algorithm; sparse hints lower to the existing logical representation.
- Added first/middle/trailing userdata and byte-pair regressions plus six invalid-index/userdata compile fixtures.
- Passed 11 root unit tests, the full test suite, and callback go-check/abi-check with unchanged generated output.
