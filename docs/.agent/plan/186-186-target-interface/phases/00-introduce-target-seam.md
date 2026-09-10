---
perf_phase: false
status: in-progress
---
> DONE-WHEN: `grep -n 'pub fn' src/gen/naming.zig` lists only neutral transforms, C ABI
> NEXT: none

# Introduce the Target seam with Go behind it

## Planned Work

- Add `src/gen/targets.zig` with `Target`, `VTable`, `Formatter`, `go`, `all`,
  `default` and `byName`, and `src/gen/targets/go.zig` holding the Go answers.
  Wire a `targets` module importing `naming` and `semantic` into
  `build/modules.zig`, `build.zig` and `build/tests.zig`, and run its tests
  from the root `test` step the way `naming`'s already run.

  The plan first said `target.zig` and a `target` module. Both the singular
  and the plural spelling are taken as local names: this repository already
  calls a build platform a target (`Options.CgoTarget`, `target_types.zig`,
  `std.Build.ResolvedTarget`), and `const target = @import("target")` shadowed
  locals in `src/gen/emit/public.zig`, `src/gen/emit/emit.zig` and
  `src/gen/validate/functions.zig`. The plural reads as the registry it is,
  and `Target` stays the singular type.
- Add `src/gen/targets/go_words.zig`, a `std`-only leaf holding `isKeyword`,
  `isIdentifier`, `isConversionFunctionName` and `validatePackageName`, which
  `go.zig` re-exports into the vtable. `build.zig` validates `go_package` and
  the `raw_package` basename before any module graph exists, so it cannot
  import a file that imports the `semantic` module; this leaf is what it
  imports instead, and it keeps one definition of each word-level rule.
- Move out of `src/gen/naming.zig`, bodies unchanged: `isGoKeyword`,
  `isGoIdentifier`, `validateGoPackageName`, `goParamNamesAlloc` with its
  `reserved_locals` table and `isReservedLocal`, `libraryPathEnvironmentAlloc`,
  `variantTypeNameAlloc` and `unionFileStemAlloc`, together with the tests that
  cover them. `containsName` is needed on both sides, so it becomes `pub` in
  `naming.zig` rather than being duplicated.

  `ownerPascalAlloc` stays in `naming.zig`. The plan listed it as a Go rule on
  the strength of its doc comment, but its body pascal-cases each segment of a
  dotted path and joins them, which is the same kind of neutral transform as
  `pascalAlloc`; its two callers are in `src/gen/lower.zig`, which is
  target-independent. Only the comment was Go-flavoured, and it is reworded.
- Move `publicFunctionNameAlloc` from `src/gen/ir/semantic.zig` to
  `targets.zig`, reading the `go.name` override through a vtable entry so a
  sibling namespace can answer it later.
- Repoint every caller. Callers in front of the seam --
  `src/gen/validate/**`, `src/reflect/packages.zig`, `src/reflect/walk.zig`,
  `src/plugin/interfaces.zig`, `src/gen/abi_diff.zig`, `src/gen/report.zig`,
  `src/gen/generator.zig`, `src/main.zig`, `build.zig` -- go through a `Target`
  value, which in this phase is `target.default` at the call site; phase 1
  makes it an argument. Callers behind the seam (`src/gen/emit/**`) call
  `targets/go.zig` directly. `src/gen/generator.zig` and `src/main.zig` turn
  out to name no Go rule at all today, so they are first touched in phases 1
  and 2.
- Give the target its own `isConversionFunctionName` and point the two private
  copies of `isGoIdentifier` in `src/gen/validate/types.zig` and
  `src/gen/validate/functions.zig` at it.

  The plan said to delete them in favour of the target's identifier predicate.
  Reading them showed that is not a refactoring: both copies are deliberately
  laxer than `naming.isGoIdentifier` -- they accept a keyword and they accept
  `_` -- because they judge the `to_raw` and `from_raw` of a `.go` adapter,
  which name functions in the user's own package rather than identifiers this
  generator invents. Folding them into `isIdentifier` would newly reject
  documents that pass today. They are a rule of their own, so the target gets
  a member of its own and the two duplicates collapse into it with the body
  unchanged.

## Done When

- `grep -n 'pub fn' src/gen/naming.zig` lists only neutral transforms, C ABI
  names and `freeParamNames`, and no `pub fn` name contains `Go`.
- `grep -rn 'isGoKeyword\|isGoIdentifier\|validateGoPackageName\|goParamNamesAlloc\|libraryPathEnvironmentAlloc\|semantic.publicFunctionNameAlloc'`
  over `src`, `build`, `build.zig`, `plugins` and `tests` returns nothing.
- Root `zig build test --summary all` passes; every example passes
  `zig build test go-check go-lib abi-check go-coverage` and `go test ./...`.
- `scripts/update-generator-cases.sh` leaves `git status --short
  tests/generator_cases` empty, which is what proves the caller set was found
  in full: a rule that moved and lost a caller would move a snapshot.
