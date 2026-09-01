---
depends_on:
- "58-float-callback-windows#0"
perf_phase: false
status: planned
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
