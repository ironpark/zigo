---
perf_phase: false
planr_base: sha256:dad5c1bb78617fa449cd64cd7aea0e841a9e6240b7d48c06f65166605f2bcc94
planr_edit: "float-callback-windows#0"
planr_phase: 0
planr_slug: bits-marshalling
planr_target: docs/.agent/plan/58-float-callback-windows/phases/00-bits-marshalling.md
status: in-progress
---
> DONE-WHEN: 08 generates and cross-builds for windows from this host; all local
> NEXT: none

# Uniform bit-marshalled float callback parameters

## Planned Work

- Change purego callback emission: shim invoke `@bitCast`s float params
  to integer bits; header typedefs use the integer types with
  real-type comments; Go dispatchers rebuild floats via
  `math.Float*frombits`; user-facing callback types unchanged.
- Verify and wire the ABI-compatibility recording so the callback ABI
  change is visible to abi-check (stale-library-vs-new-Go mismatch must
  fail loudly); record how in the phase notes.
- Retire or narrow ZIGO014 in `validate.zig` + tests per the analysis;
  windows-target generation of 08-telemetry-hub must succeed.
- Update goldens; regenerate all four purego trees; POSIX suites green;
  `GOOS=windows go vet/build` clean; export-table/cross-build spot
  check for 08's windows DLL using the plan-56/57 procedures.

## Done When

- 08 generates and cross-builds for windows from this host; all local
  suites green; goldens updated; ABI recording decision documented.
