---
completed_at: "2026-09-01T23:48:14Z"
depends_on:
- "63-error-union-slice-payloads#0"
perf_phase: false
status: done
---
> DONE-WHEN: The fallible caller-owned fixture passes on cgo and purego with the leak
> NEXT: none

# Caller-owned release for error-union slice payloads

## Planned Work

- validate: ZIGO016 matching accepts `.returns = .caller` when the return is an
  error union whose payload is a slice; the release parameter type must equal
  the payload slice type; missing/mismatched release keeps the ZIGO016 snapshot
  behaviour (add snapshot cases for the error-union form).
- lower: `release_symbol` resolution unchanged; confirm it applies to the
  error-union function.
- emit raw: call the release symbol only on `code == 0` after the copy, on
  both backends.
- abi_diff: release change on an error-union slice function is breaking (add a
  test).
- Example: `EventQueue.extractSamplesChecked(self) ![]f32` with
  `.returns = .caller, .release = "EventQueue.freeSamples"`, failing on a flag;
  Go tests assert the copy survives a second call, `liveSamples()` returns to
  zero after success, and stays unchanged after a failed call (nothing was
  allocated or released).
- Docs: `bindings.md` ownership section states that release runs only on
  success for error-union payloads; 03 §8 row.

## Done When

- The fallible caller-owned fixture passes on cgo and purego with the leak
  counter at zero after success and untouched after failure; ZIGO016 snapshots
  cover the error-union form; abi-check test added; docs updated; committed.
