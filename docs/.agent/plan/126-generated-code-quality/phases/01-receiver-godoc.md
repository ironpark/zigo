---
completed_at: "2026-09-05T23:02:20Z"
perf_phase: false
status: done
---
> DONE-WHEN: No example has two receiver spellings for one type; `zig build test` passes.
> NEXT: none

# Receiver names and GoDoc first line

## Planned Work

- `typeReceiverNameAlloc` in `common.zig` with a unit test; switch every call
  site; keep `receiverVariableAlloc` only if something still needs it.
- `writeGoDoc` first-line join; unit test.
- Regenerate cases and examples; note in `generated-runtime.md` and CHANGELOG.

## Done When

- No example has two receiver spellings for one type; `zig build test` passes.
