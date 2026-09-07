---
perf_phase: false
status: in-progress
---
> DONE-WHEN: All three reproductions pass with fixes and the repository test suite passes.
> NEXT: none

# Fix plugin review findings

## Planned Work

- Fix each reviewed defect and add regression coverage.
- Run focused and full tests, inspect the diff and commit the changes.

## Done When

- All three reproductions pass with fixes and the repository test suite passes.

## Implementation and verification

- Preserve explicit null in serialized plugin options, including nullable fields with non-null defaults and required nullable fields. Reflection regression covers both function and type declarations through semantic serialization and parsing.
- JSON wire fields now preserve the codepoint semantic hint as rune. The JSON golden includes a codepoint field; a Go test compiles the generated public files against a minimal raw layout stub and verifies JSON round trips for zero, Korean, emoji and the maximum Unicode codepoint.
- Validation and emission use the registry's shared plugin selection rule. Generator regression checks empty, explicit and default selections and confirms built-in validation remains active. The disabled-plugin golden covers both malformed JSON options and a SATIS custom validation error.
- `zig build test -Dtest-filter=plugin`: passed after regenerating the affected golden fixtures.
- `zig build test`: passed, including generated Go compilation and runtime round trips.
- `zig fmt --check` for changed Zig sources and `git diff --check`: passed.

The raw stub in the Go regression isolates generated methods from native linking; native golden checks remain part of the full test suite.
