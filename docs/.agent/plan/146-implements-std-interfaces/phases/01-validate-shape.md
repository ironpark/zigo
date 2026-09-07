---
completed_at: "2026-09-07T08:07:05Z"
depends_on:
- "146-implements-std-interfaces#0"
perf_phase: false
status: done
---
> DONE-WHEN: Each rejected shape has a test; a hand-written `semantic.json` with a bad shape fails
> NEXT: none

# Validation ZIGO058

## Planned Work

- `implementsIssue` in `src/gen/validate/functions.zig`: receiver required and a
  registered handle; exactly the parameter shape the interface needs; result `void` or
  integer (`.reader`: integer via `.written = .result`); no `.cancel`, `.iterator`,
  callback or stream-accessor combination; no text hint on the `.writer` slice.
- Program-wide checks: one method per (receiver, interface); wrapper name not already a
  Go method name on that receiver.
- Every message names the method, the interface, and the expected shape; hints point at
  the fix (`drop .semantic = .utf8_string`, `add .written = .result`, ...).
- Unit tests per rule; `docs/diagnostics.md` gets the `ZIGO058` section and the
  cheatsheet row.

## Done When

- Each rejected shape has a test; a hand-written `semantic.json` with a bad shape fails
  `zigo-gen` with `ZIGO058` only.
