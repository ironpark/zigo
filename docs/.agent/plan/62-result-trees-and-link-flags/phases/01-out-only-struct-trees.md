---
entry_condition: Plan 61 phases 1 and 4 are done (struct slice elements and slice release exist) and the maintainer confirms the out-only axis over the opaque-accessor alternative.
perf_phase: false
status: in-progress
---
> DONE-WHEN: A three-level out-only tree deep-copies in one call on cgo and purego; in-
> NEXT: none

# Out-only deep-copied value struct trees

## Planned Work

- Design first: write the metadata shape and the copy algorithm into 03 §6 and
  `02-ir-spec.md` (new `TypeDecl` flag, field-pair metadata, eligibility rules,
  release interaction, error mapping for allocation failure during copy).
- reflect/validate: accept `(ptr, len)`/`(ptr, count)` field pairs on out-only
  structs; `ZIGO012` remains for in-direction structs and for unpaired
  pointers; a new diagnostic for an out-only struct used as a parameter or in a
  callback.
- lower/emit: recursive copy in cgo (unsafe.Slice over C pointers) and purego
  (unsafe.Slice over uintptr) into idiomatic Go types (`string`, `[]T`); one
  native call per tree; release called once after the copy for caller-owned
  returns.
- abi_diff: field-pair metadata participates in signature equality.
- Fixture shaped like `Probe` (three nesting levels, text and array fields) on
  both backends with a Go test comparing the tree to expected values.
- Until this phase runs, `limitations.md` states that result trees must be
  redesigned as handles and that each accessor is one native call under the
  handle's `RWMutex`.

## Done When

- A three-level out-only tree deep-copies in one call on cgo and purego; in-
  direction use is a diagnostic; docs and goldens updated; committed. If the
  maintainer declines, `limitations.md` carries the cost note and the phase is
  marked done with that outcome recorded here.
