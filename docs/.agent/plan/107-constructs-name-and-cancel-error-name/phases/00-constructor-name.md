---
perf_phase: false
status: planned
---
> DONE-WHEN: `.constructs = "AudioBuffer", .name = "extractAudio"` yields `ExtractAudio` in Go with working lifecycle, and the loop passes.
> NEXT: none

# Honor .name on constructors

## Planned Work

- Track whether `.name` was explicit; use it for the constructor's Go name; keep lifecycle lookups by function identity; generator case; abi-diff; docs; CHANGELOG. If a constructor kind cannot honor it, emit a diagnostic instead of silently ignoring.

## Done When

- `.constructs = "AudioBuffer", .name = "extractAudio"` yields `ExtractAudio` in Go with working lifecycle, and the loop passes.
