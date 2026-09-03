# GOALS

## Problem and the end result from the user's point of view

ABI classification is re-derived in several files with predicates that have quietly diverged:

- `functionHasCallback` (lower.zig, validate.zig): identical.
- `isStringSliceParameter` (lower, validate, emit): lower/validate identical; emit uses `stringSliceForm` and also accepts `[*:0]const u8` elements.
- `isCStringSlice` (lower, emit): emit looks through `.optional`, lower does not; lower handles optionals in separate branches (`lower.zig` parameter branch near line 72 and return branches near lines 269/351).
- `sliceReturnElement` (validate, emit): same name, different concept. validate includes caller-owned C-string returns (they need a release target); emit excludes them (they cross as a pointer, not out-pointer plus length).
- `constructorForInit` (emit, report): report keeps a `receiver != null` guard that is stale since method constructors (plan 75).
- `abi_diff.zig` `typeEqual` (~line 434) re-models what lowering ignores by hand instead of comparing lowered programs.

End result: one definition per fact, decided in lowering and recorded on `abi.Program`; the emitter reads classifications instead of recomputing them; `abi-diff` compares the lowered C shape of both documents and keeps semantic comparison only for what lowering does not carry (names, packages, docs). Generated output is byte-identical throughout, except the `report` command output for method constructors, which is a bug fix.

## Measurable goals

- No two files define a predicate with the same name and different bodies; concept-different pairs get distinct names.
- `abi.AbiParam` (or `AbiFn`) carries the string role (utf8 slice, C string, string slice form), callback/userdata pairing, callback type name, and struct castability, populated in `lower.zig`; the corresponding predicates in `emit.zig` are deleted.
- Each divergence resolved by an explicit decision recorded in a code comment and, where reachable, a unit test: (a) whether `[]const [*:0]const u8` parameters are accepted (validate must agree with lower and emit), (b) optional C-string returns keep their current lowering, (c) report follows emit for method constructors.
- `abi_diff` lowers both documents (`lower.semanticDocumentForBackend`) and compares `abi.Program` for C-shape equality; classification of breaking versus compatible keeps its current results on every existing abi-diff test.
- No file under `tests/generator_cases/*/expected` or committed example generated file changes; `zig build test`, fmt, all 11 examples on cgo and purego green.

## Supported scope and non-goals

In scope: `src/gen/ir/abi.zig`, `src/gen/ir/semantic.zig` (methods only), `src/gen/lower.zig`, `src/gen/emit.zig`, `src/gen/validate.zig`, `src/gen/report.zig`, `src/gen/abi_diff.zig`, tests.
Non-goals: new metadata, new diagnostics, any change to semantic.json or generated files.

## Reference source / commit / license

Current main; plan 95 (lowering-owned ABI tables) is the pattern to follow.

## Completion criteria for the whole plan

Three phases done; verification loop green; goldens and examples unchanged; tree clean.
