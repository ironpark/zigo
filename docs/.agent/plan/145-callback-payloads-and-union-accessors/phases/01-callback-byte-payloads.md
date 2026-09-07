---
completed_at: "2026-09-07T08:06:28Z"
perf_phase: false
status: done
---
> DONE-WHEN: The example callback with string payloads passes on cgo and purego; goldens updated.
> NEXT: none

# Callback string and byte payloads

## Planned Work

- Reflect the `[*]const u8` + `usize` pair and `[*:0]const u8` in callback signatures with string hints.
- Lower to ptr+len or `const char *` wire slots; teach shim, cgo export, purego dispatcher and public type writers about the slot mapping.
- Allow byte slices in ZIGO057; add generator cases, example coverage, docs, changelog.

## Done When

- The example callback with string payloads passes on cgo and purego; goldens updated.
