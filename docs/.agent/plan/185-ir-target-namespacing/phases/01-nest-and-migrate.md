---
depends_on:
- "185-ir-target-namespacing#0"
perf_phase: false
status: planned
---
> DONE-WHEN: Written documents carry `"ir_version": 2` and nest the moved fields under `go`.
> NEXT: none

# Nest the fields and migrate the document

## Planned Work

- Add `ParamGo`, `FnGo` and `TypeGo` to `src/gen/ir/semantic.zig` and move
  `go_adapter`, `go_error`, `go_name`, `go_owner` and `return_go_adapter` onto
  them as `adapter`, `callback_error`, `name`, `owner` and `return_adapter`.
  `iterator` and `implements` stay where they are; phase 2 moves them.
- Repoint the phase 0 accessors at the nested fields so no reader changes again.
- Update the five writer sites — `src/reflect/walk.zig`, `src/normalize.zig`,
  `src/reflect/pairing.zig`, `src/plugin/rename.zig` and the `map_type` and
  rename plugin hooks in `src/gen/validate/validate.zig` — to build the
  namespace.
- Make the `go` object omitted when every member is null, so bindings that use
  no Go knob serialize unchanged.
- Set `ir_version` to `2` and teach `Semantic.parse` to lift a version-1
  document into the nested shape, with a unit test asserting a version-1 fixture
  and its version-2 equivalent parse to the same `Semantic`.
- Regenerate snapshots with `scripts/update-generator-cases.sh` and review the
  diff: it must touch `semantic.json` only.

## Done When

- Written documents carry `"ir_version": 2` and nest the moved fields under `go`.
- The version-1 parse test passes.
- The regenerated diff under `tests/` and `examples/` contains no file other
  than `semantic.json`; every generated Go, shim and header file is unchanged.
- `zig build test go-check abi-check go-coverage --summary all` passes.
