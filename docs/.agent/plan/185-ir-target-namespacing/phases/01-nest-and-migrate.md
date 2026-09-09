---
depends_on:
- "185-ir-target-namespacing#0"
perf_phase: false
status: in-progress
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
- Update the four writer sites — `src/reflect/walk.zig`,
  `src/reflect/pairing.zig`, `src/plugin/rename.zig` and the `map_type` and
  rename plugin hooks in `src/gen/validate/validate.zig` — to build the
  namespace through setters. `src/normalize.zig` is not among them after all:
  its `go`, `go_error` and `go_name` writes land on `src/declare.zig`'s `Param`,
  which is the author-facing DSL this plan leaves alone.
- Make the `go` object omitted when every member is null, so bindings that use
  no Go knob serialize unchanged.
- Set `ir_version` to `2` and teach `Semantic.parse` to lift a version-1
  document into the nested shape, with a unit test asserting that a version-1
  fixture and its version-2 spelling parse to the same `Semantic`, and that a
  version-1 document with no Go-specific field gains no `go` object.
- Move the `ZIGO020` gate in `src/gen/validate/validate.zig` off the literal `1`
  and onto the current version, and update the tests that pin one: the
  `ZIGO020` snapshot case and the two `abi_diff` documents that used `2` to mean
  "different from the default".
- Fix the readers outside `src`: `plugins/enumkit` reads `TypeDecl.go_adapter`
  directly, and `tests/plugins/transform_observer.zig` reads `go_name` and
  `return_go_adapter`.
- Leave the generator cases' version-1 inputs as they are and confirm
  `scripts/update-generator-cases.sh` produces no diff at all. Seventy version-1
  documents regenerating byte-identical `expected/` trees is the migration's
  real proof, and a synthetic fixture could not give it. Regenerate the 13
  `examples/*/zigo/semantic.json` outputs with `zig build go` and review that
  diff.

## Done When

- Written documents carry `"ir_version": 2` and nest the moved fields under `go`.
- The version-1 parse test passes.
- `scripts/update-generator-cases.sh` leaves `tests/generator_cases` clean.
- The only regenerated files under `examples/` are the 13 `semantic.json`
  outputs, and their diff is the version line plus the moved fields; every
  generated Go, shim and header file is unchanged.
- `zig build test --summary all` passes at the repository root, and
  `zig build test go-check go-lib abi-check go-coverage` followed by
  `go test ./...` passes in every example.
