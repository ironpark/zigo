---
perf_phase: false
status: in-progress
---
> DONE-WHEN: Both backends compile generated public and external tests and raw additions.
> NEXT: none

# Output contracts

## Planned Work

- Add GoFile and Artifact contracts, explicit scope and package targets, and build constraint validation.
- Route outputs separately and preserve exact artifact bytes while checking all paths and collisions before writing.
- Migrate builtins and external fixtures, add split-package and real Go compilation tests, and document the new contract.

- Track output ownership so the CLI formats only GoFile outputs and publishing and checks include exact artifacts.

## Done When

- Both backends compile generated public and external tests and raw additions.
- Document and package artifacts run once per intended scope, preserve exact bytes, and cannot overwrite another emitter.
- Test, check and formatting verification pass.
