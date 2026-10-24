---
completed_at: "2026-10-24T11:52:06Z"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build --help` configures without errors on 0.17.0.
> NEXT: none

# Build script on the 0.17 configure model

## Planned Work

- Move the three custom steps into generator subcommands that run as
  `Step.Run` steps.
- Replace `getPath`, `pathFromRoot`, `b.args` and `build_root` access with
  0.17 equivalents, declaring configure-time inputs.

## Done When

- `zig build --help` configures without errors on 0.17.0.
