---
completed_at: "2026-09-07T13:47:31Z"
perf_phase: false
status: done
---
> DONE-WHEN: Helpers and contextual/static/explicit receiver choices are implemented and verified without runtime changes.
> NEXT: none

# Contract helpers and contextual members

## Planned Work

- Add Param and Returns constructors and Entry.members with exact replacement semantics.
- Add explicit constructor receiver selection and validate contextual/mismatched owners.
- Add positive and compile-failure regressions and migrate affected constructor literals.

## Done When

- Helpers and contextual/static/explicit receiver choices are implemented and verified without runtime changes.

## Implementation and Verification

- Added complete param/result constructors, optional Param.named, and replacement-only Entry.members.
- Constructors distinguish none, member, and explicit type receivers; incompatible enclosing/argument types fail during normalization.
- Added a normalization regression and six compile-failure fixtures.
- Passed zig test src/root.zig, full zig build test --summary failures, and event-queue go-check/abi-check without generated changes.
