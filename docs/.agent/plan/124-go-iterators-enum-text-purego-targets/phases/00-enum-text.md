---
perf_phase: false
status: in-progress
---
> DONE-WHEN: `zig build test --summary all` passes with the new case.
> NEXT: none

# Enum text encoding

## Planned Work

- Read `.text` on `.enumeration` entries in `walk.zig`; add `TypeDecl.text`.
- Validate in `validate/types.zig`: `ZIGO051` when `.text` is set on a
  non-enum entry; document the code in `docs/diagnostics.md`.
- Emit `Parse<Enum>`, `MarshalText`, `UnmarshalText` in `renderGoEnums`, with
  the `EnumParseError` helper gated through `references.zig`.
- `abi_diff.zig`: text encoding removed is breaking, added is compatible.
- Generator case `enum_text` (cgo) pinning exhaustive and open enums.
- Add `.text = true` to `QueueSignal` in `examples/07-event-queue`, regenerate,
  and add a Go test for parse/marshal round trips.
- Docs: `bindings-types.md` enum section, `generated-runtime.md`, CHANGELOG.

## Done When

- `zig build test --summary all` passes with the new case.
- `examples/07-event-queue` passes `zig build go-check abi-check` and `go test`
  including the round-trip test.
