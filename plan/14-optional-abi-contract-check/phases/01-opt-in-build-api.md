---
depends_on:
- "14-optional-abi-contract-check#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: A minimal consumer without ABI configuration compiles without an ABI check step, opted-in examples retain `abi-check`, and all repository checks pass.
> NEXT: none

# Make compatibility policy opt-in

## Planned Work

- Change the public build options and result so the ABI baseline and check handle are optional.
- Construct the Git baseline and diff run step only when a baseline is configured.
- Opt repository examples into `HEAD` explicitly and update their step wiring.
- Update README, wiki, and architecture documentation to explain when to enable compatibility checking.

## Done When

- A minimal consumer without ABI configuration compiles without an ABI check step, opted-in examples retain `abi-check`, and all repository checks pass.
