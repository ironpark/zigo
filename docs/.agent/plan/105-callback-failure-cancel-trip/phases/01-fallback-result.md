---
completed_at: "2026-09-03T06:34:33Z"
depends_on:
- "105-callback-failure-cancel-trip#0"
perf_phase: false
status: done
---
> DONE-WHEN: A callback with `.on_callback_failure = .{ .result = 0 }` returns 0 on panic and the panic is still rethrown after the call; validation rejects a value that does not fit.
> NEXT: none

# Declared fallback result

## Planned Work

- `.on_callback_failure = .{ .result = N }` metadata, semantic field, validation, dispatcher emission, abi-diff classification, generator case, docs, CHANGELOG.

## Done When

- A callback with `.on_callback_failure = .{ .result = 0 }` returns 0 on panic and the panic is still rethrown after the call; validation rejects a value that does not fit.
