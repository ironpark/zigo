# GOALS

## Problem and the end result from the user's point of view

The generated artifacts do not change at all; this is an internal correctness
guard. Today two modules decide what a C typedef is called. `lower.zig` mints
`<prefix>_<snake>` for value structs and snapshots and stores it in the IR, but
`emit.zig` re-derives the same string for enums, opaque handles, and tagged
union receivers. A change to the naming rule has to be made in both places, and
a partial change produces a header whose typedefs and whose function signatures
disagree — a C compile error in the user's project, not a generator error.

Afterwards, lowering is the only module that spells a C type name, and the
emitter only reads names the IR already carries.

## Measurable goals

- `emit.zig` contains no `{s}_{s}` format of `program.prefix` with a type name.
- `emit.zig` calls `naming.snakeAlloc` only for the package name and for Zig
  shim identifiers, never to build a C type or C constant name.
- The cgo emitter contains no `structRecord(...).?` for a function's own
  parameter or return struct.
- Every generated artifact under `tests/` and `examples/` is byte-identical
  before and after.

## Supported scope and non-goals

In scope: `src/gen/ir/abi.zig`, `src/gen/lower.zig`, `src/gen/emit.zig`, and
the tests covering them.

Not in scope: Go-side naming (`pascalAlloc` for Go identifiers stays in the
emitter, because it is the Go backend's own concern and purego and cgo spell it
the same way from one helper); the padding-member proposal for `AbiStruct`,
which was reviewed and rejected; `validate.zig`'s `externStructFieldEligible`
recursion, also reviewed and rejected.

## Reference source / commit / license

None. This reorganises code already in this repository.

## Completion criteria for the whole plan

`zig build test`, `zig build check`, and the golden-artifact comparison all
pass, and the four measurable goals above hold.
