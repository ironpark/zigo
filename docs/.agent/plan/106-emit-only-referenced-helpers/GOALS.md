# GOALS

## Problem and the end result from the user's point of view

Generated Go contains helpers nothing references: `zigo<T>SliceView` (every castable struct, `emit.zig` renderPublicStructs), `zigo<T>ToRaw` (structs only read back), `boolToUint8` (a bool struct field whose struct is only returned), `zigoOptionalPointer` (every program with opaque types), `activeCallbackHandleCount` (every program with callbacks). `go vet` passes but `staticcheck` U1000 fails, and reviewed generated code carries dead functions. End result: each helper is emitted only when a use site exists, and CI runs `staticcheck -checks U1000` over every example's generated packages so regressions are caught.

## Measurable goals

- One predicate per helper (`programUses...`) derived from the same walk that emits the use sites; tests in `emit.zig` for each helper's present/absent case (documents built through real structures, no `undefined`).
- `staticcheck -checks U1000 ./...` clean in every example go.mod (cgo and purego); a CI job installs and runs it.
- Goldens updated only where a helper disappears; generated public API unchanged.
- CHANGELOG `## [Unreleased]` `### Changed`.

## Supported scope and non-goals

In scope: `src/gen/emit.zig` helper emission, generator case goldens, examples, `.github/workflows/ci.yml`. Non-goals: the raw layer's exported functions (they are API), tests that intentionally reference helpers.

## Reference source / commit / license

Current main; `programNeedsBoolHelper`, `renderPublicHelpers`, `renderGoHandleRuntime`, the `record.castable` branch in struct helper emission.

## Completion criteria for the whole plan

Both phases done; verification loop green; tree clean.
