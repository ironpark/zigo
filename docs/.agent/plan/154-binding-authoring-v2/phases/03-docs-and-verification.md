---
depends_on:
- "154-binding-authoring-v2#2"
perf_phase: false
status: in-progress
---
> DONE-WHEN: The new API is documented, required checks pass and the working tree is clean.
> NEXT: none

# Documentation and final verification

## Planned Work

- Document the new authoring model, contract semantics, migration and limitations; update changelog and examples.
- Run format checks, generated-tree checks for cgo/purego examples and focused Go behavior checks.
- Review and commit the final result and close the plan.
- Completed: updated the authoring guides, cheatsheet, plugin contract, examples and Unreleased changelog; added migration-authoring.md with breaking changes and current limits.
- Final review found enum covers must resolve after all type registrations; fixed renamed/forward owner references and added a coverage regression test.
- Installation examples now target the development branch; release fetch replacement accepts either a version ref or main. The historical 0.15 migration script is explicitly labeled as intermediate only.
- Verification: zig build test passed 299/299 steps and 761/761 tests, including 17 compile-failure cases; zig build check passed 24/24 steps.
- All 13 examples passed Zig tests, go-check, go-lib, abi-check, go-coverage and fresh cgo Go tests. All 7 purego example modules passed generated-tree checks, library builds and Go tests with CGO_ENABLED=0.
- Format checks, git diff --check, local documentation links and release shell syntax/substitution checks passed. No version bump, push or release was performed for this work.

## Done When

- The new API is documented, required checks pass and the working tree is clean.
