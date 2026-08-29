---
depends_on:
- "01-zigo-go-bindings#4"
perf_phase: false
status: planned
---
> DONE-WHEN: `errors.Is(err, mylib.ErrDivideByZero)` holds in the example's Go tests.
> NEXT: none

# Error unions and slices

## Planned Work

- Lower error unions to a stable integer return plus a payload out-parameter, using the
  error lock; omit the out-parameter when the payload is void; leave the payload
  untouched on the error path.
- Reject `anyerror` returns as ZIGO001 and non-exhaustive enums as ZIGO002.
- Lower enums to a fixed-width integer with C constants, a Go named type and a generated
  `String` method.
- Split slices into pointer plus length, appending a written-count out-parameter for
  output slices.
- Reject slices whose element type contains a pointer as ZIGO005, since Go forbids
  passing Go memory that holds Go pointers.
- Emit the Go error type, sentinel values and `errors.Is` support.
- Add `examples/02-errors` with a failing division and a slice sum.

## Done When

- `errors.Is(err, mylib.ErrDivideByZero)` holds in the example's Go tests.
- Regenerating leaves `errors.lock.json` codes unchanged; a hand-edited mapping is
  rejected.
- Summing a `[]float64` from Go returns the value computed in Zig.
- ZIGO001, ZIGO002 and ZIGO005 each have a diagnostic snapshot test.
