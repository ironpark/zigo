---
completed_at: "2026-09-06T06:54:53Z"
depends_on:
- "134-callback-thunk-and-userdata#0"
perf_phase: false
status: done
---
> DONE-WHEN: Existing snapshots unchanged; the new case dispatches on the declared slot; the diagnostic has a function site.
> NEXT: none

# Declared userdata position

## Planned Work

- Replace `Callback.has_userdata` with `userdata_index: ?usize` (JSON field kept in sync, abi_diff compares it).
- Callback type entries accept `.userdata = .last | .first | .{ .index = n }`; `param_meta.<cb>.userdata = "name"` names the function-side token.
- Thunk reorders arguments to the Go convention when the index is not last.
- Move `error.CallbackRequiresUserdata` into a validate diagnostic (new code) covering the callback slot type and the function token parameter.
- Generator case with userdata first.

## Done When

- Existing snapshots unchanged; the new case dispatches on the declared slot; the diagnostic has a function site.
