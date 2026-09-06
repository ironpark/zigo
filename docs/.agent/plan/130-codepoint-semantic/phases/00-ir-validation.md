---
completed_at: "2026-09-06T02:29:31Z"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test` passes with the new tests; `docs/diagnostics.md` has the `ZIGO053` entry.
> NEXT: none

# IR, validation and diff

## Planned Work

- Add `codepoint` to `SemanticHint`, plus `isCodepoint` / `isCodepointSlice` predicates with unit tests.
- Add `ZIGO053` in `validate/functions.zig` rejecting `.codepoint` on anything but a plain `u21`/`u32` scalar or plain slice of one (in/out, return, error payload, optional scalar return), and on injected/flatten parameters.
- Reflection test that `param_meta` and function `.semantic = .codepoint` are recorded; abi_diff test that adding the hint is breaking.

## Done When

- `zig build test` passes with the new tests; `docs/diagnostics.md` has the `ZIGO053` entry.
