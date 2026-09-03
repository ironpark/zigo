# GOALS

## Problem and the end result from the user's point of view

Two follow-ups from plan 96 and the 0.7.2 fixes.

1. `zigo-gen abi-diff` now lowers both documents (plan 96). Lowering assumes a validated document: `lower.zig` `typeDeclaration` (and `typeDeclarationNamed`-style helpers) hit `unreachable` when a type reference has no declaration, so a hand-edited or truncated `semantic.json` handed to `abi-diff` panics instead of reporting. Generator-produced documents are always validated first, so this only affects `abi-diff` with foreign inputs, but a CLI must not abort with a stack trace on bad input. End result: `abi-diff` validates both inputs (or lowering becomes fallible) and prints a diagnostic naming the file and the missing declaration, exit code as for other input errors.

2. The generator case test steps did not rerun after `tests/generator_cases/flattened_options/semantic.json` changed: `zig build test` reported `generator case (flattened_options) cached` while the runner, invoked by hand, produced a different tree. `addGeneratorCases` in `build.zig` passes the case directory with `run.addDirectoryArg`; either the directory hash does not cover nested file contents the way this step needs, or the runner's inputs are not fully declared. End result: editing any file under a case directory (semantic.json, options.json, expected/*) reruns that case's step.

## Measurable goals

- `abi-diff --base bad.json --current good.json` where `bad.json` references an undeclared type exits non-zero with a one-line diagnostic (no panic, no stack trace); a CLI test in `build.zig`/`tests/fixtures/cli/abi` pins it. Decide between (a) running `validate` on both inputs before lowering, reusing the existing ZIGO diagnostics, and (b) making `typeDeclaration` return an error through lowering; prefer (a) if it needs no signature churn, but the panic must be unreachable either way. Document the precondition change on `lowerFor`.
- A test or reproducible check that a case step reruns after its `semantic.json` changes (for example: change a golden's input, run `zig build test`, confirm the step is not `cached`); fix `addGeneratorCases` (declare files explicitly with `addFileArg`/per-file dependencies, or use `addDirectoryArg` on the exact inputs the runner reads, or mark the step with `has_side_effects` only as a last resort and justify it).
- No generated output changes; all goldens and examples unchanged; full verification loop green.

## Supported scope and non-goals

In scope: `src/gen/abi_diff.zig`, `src/gen/cli.zig`, `src/gen/lower.zig` (only if choosing fallible lowering), `build.zig` `addGeneratorCases`/`addGoldenArtifactChecks`, tests and fixtures, `docs/development.md` if the case workflow changes.
Non-goals: new diagnostics codes beyond reusing validation, changes to the case format.

## Reference source / commit / license

Current main (`7eac547`); plan 96 for `lowerFor` in abi_diff.zig; plan 87/90 sessions where snapshot updates were done via `zig build snapshot -- <expected> <actual> --update-snapshots`.

## Completion criteria for the whole plan

Both phases done; verification loop green; tree clean.
