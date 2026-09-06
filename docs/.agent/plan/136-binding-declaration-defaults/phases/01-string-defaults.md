---
perf_phase: false
status: in-progress
---
> DONE-WHEN: A binding that sets both writes `.returns = .caller` alone for a
> NEXT: none

# Define-level string defaults

## Planned Work

- `.strings = .infer_utf8` marks every plain `[]const u8` parameter and return
  (and `[]const []const u8`) as `.utf8_string`, through `!` and `?`, with
  `.opaque_bytes` as the per-site opt-out and an explicit hint always winning.
- `.string_release = "root.freeString"` supplies `.release` for a
  `.returns = .caller` string result that does not name one.
- Reject the combinations that cannot mean anything, reusing the existing
  release diagnostics rather than adding a code where one fits.
- Reflection tests for inference, opt-out, explicit override, and the default
  release; one generator case pair.

## Done When

- A binding that sets both writes `.returns = .caller` alone for a
  caller-owned string, and goldens for bindings that set neither are unchanged.
