---
completed_at: "2026-09-06T03:17:27Z"
perf_phase: false
status: done
---
> DONE-WHEN: Tests green; example 02 `CodepointWidth(0x110000)` and `(-1)` return `ErrOutOfRange` with `Type == "codepoint"`.
> NEXT: none

# Unicode range and u21 inference

## Planned Work

- Range check every codepoint parameter against `0..0x10FFFF` with `Type: "codepoint"`; extend `needsCheck`/`reportsPanics` so `u32` codepoint parameters add `error`.
- Add `.integer` opt-out hint (recorded as null) and the `.codepoints = .infer_u21` define option in reflection, with tests.
- Refresh goldens, examples 02/11 tests and docs (`bindings-types.md` 코드포인트, CHANGELOG).

## Done When

- Tests green; example 02 `CodepointWidth(0x110000)` and `(-1)` return `ErrOutOfRange` with `Type == "codepoint"`.
