---
depends_on:
- "01-zigo-go-bindings#8"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Editing a generated file makes `zig build go-check` fail and name that file.
> NEXT: none

# Source sync check and ABI diff

## Planned Work

- Implement the check mode: generate, compare against `go_dir`, report the differing
  files and exit non-zero without writing anything.
- Implement `--abi-diff --base <ref>`, reading the baseline through
  `git show <ref>:zigo/semantic.json`.
- Classify changes: removal, signature change and error-code reassignment as breaking;
  added functions, types and appended errors as compatible; and treat a change in return
  ownership or retention as breaking, because it silently changes who frees memory.
- Add `--fail-on breaking` and a `--json` report format.
- Expose both as the `check` and `abi_check` steps.

## Done When

- Editing a generated file makes `zig build go-check` fail and name that file.
- Changing a parameter type is reported as BREAKING; adding a function is reported as
  ADDED; appending an error is reported as ABI COMPATIBLE.
- `zig build go-check abi-check` passes on a clean, current tree.
