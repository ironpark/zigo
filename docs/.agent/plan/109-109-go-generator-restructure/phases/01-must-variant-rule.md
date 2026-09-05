---
depends_on:
- "109-109-go-generator-restructure#0"
perf_phase: false
status: planned
---
> DONE-WHEN: `grep -rn "Close"` under `src/gen` shows one Must-variant exclusion.
> NEXT: none

# One Must-variant rule in lowering

## Planned Work

- Add `AbiFn.must_variant: bool` set in `lower.zig` from the conditions emit uses
  today (`constructor`, `needs_check` parts, error-union return, not `Close`).
- `emit/must.zig` reads the field; delete emit's inline condition.
- `validate.findMustVariantIssue` takes `abi.Program`; `main.zig` and
  `generator.zig` lower before calling it. Delete `mustVariantEligible`.
- Add a validate test for a free function whose callback signature is flagged
  as error-bearing on another function (the case the two rules disagreed on).

## Done When

- `grep -rn "Close"` under `src/gen` shows one Must-variant exclusion.
- Goldens unchanged; new test passes; `zig build test` green.
