---
depends_on:
- "01-zigo-go-bindings#7"
perf_phase: false
status: planned
---
> DONE-WHEN: Each of ZIGO001 through ZIGO009 has a snapshot test asserting its message and hint.
> NEXT: none

# Diagnostics completed

## Planned Work

- Implement the remaining rejections: ZIGO004 for a function pointer that is not
  `callconv(.c)`, ZIGO006 for a tagged union, ZIGO007 for a symbol-name collision, and
  ZIGO009 for a retained pointer with no matching release function.
- Never auto-number a colliding symbol; a collision is an error because renaming would
  silently change the ABI.
- Give every diagnostic a declaration site and an actionable hint.
- Guarantee that a failing validation writes no output files at all, leaving any
  previously generated tree untouched.
- Add a snapshot test per diagnostic code, so all nine are covered.

## Done When

- Each of ZIGO001 through ZIGO009 has a snapshot test asserting its message and hint.
- A validation failure leaves the output directory byte-identical to its prior state.
- The build step surfaces the generator's non-zero exit as a step failure.
