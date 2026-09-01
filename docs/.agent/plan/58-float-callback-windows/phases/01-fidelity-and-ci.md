---
completed_at: "2026-09-01T18:10:46Z"
depends_on:
- "58-float-callback-windows#0"
perf_phase: false
status: done
---
> DONE-WHEN: Windows CI green with 08 in the job — first Windows runtime proof of
> NEXT: none

# Fidelity tests, CI restoration, docs

## Planned Work

- Add float round-trip fidelity tests (ordinary value, negative zero,
  +Inf) through a callback in a POSIX-run purego suite; they also run
  on Windows once CI picks them up.
- Restore 08-telemetry-hub to the `purego-windows` CI job's native
  legs; remove/update the ZIGO014 assertion; keep the 07 cross-artifact
  leg unchanged.
- Update docs: limitations (float-callback restriction removed), purego
  ABI notes describing the bits lowering, ZIGO014 references.
- Push and follow the CI loop from plans 56–57: if the Windows run
  fails, fix as further phases; do not claim Windows runtime success
  before CI passes.

## Done When

- Windows CI green with 08 in the job — first Windows runtime proof of
  float callback params AND float purego-call args; fidelity tests
  green on both OSes; docs updated; `planr overview` shows the plan
  done.

## Notes

- Fidelity test lives in 08-telemetry-hub's purego suite
  (`TestPuregoFloatCallbackParameterIsBitExact`) and compares
  `math.Float64bits`, so a lossy conversion cannot pass by printing the
  same. Negative zero catches a dropped sign bit. `Push` refuses a
  non-finite sample, so the +Inf case is produced natively instead:
  scaled mode overflows `1e308 * 1e308` on the Zig side, which also
  makes the assertion cover a value the Go side never constructed.
- CI: 08 rejoined the `purego-windows` generation and suite legs; the
  ZIGO014 assertion block is gone, since nothing is refused for a
  windows target any more. The 07 cross-artifact job is untouched.
- One CI-only breakage from the ABI bump: the shared-artifact smoke
  check named `zg_apply_purego_v1` for 04-callback. Fixed to v2 in a
  follow-up commit; nothing else in the workflow named a versioned
  symbol.
- Windows CI green with 08 in the job (run 33541504364, all four jobs):
  the first runtime proof that float callback parameters and float
  purego call arguments both work on Windows.
