---
completed_at: "2026-09-07T10:24:45Z"
depends_on:
- "148-generator-plugins#3"
perf_phase: false
status: done
---
> DONE-WHEN: Both plugins have golden cases and example tests on both backends;
> NEXT: none

# Showcase plugins

## Planned Work

- `plugins/satisfies`: `Options = struct { interfaces: []const Import }`, `type_hook`
  emits `var _ pkg.Iface = (*T)(nil)` and a doc line; used by example 11's `Document`
  (`io.ReadWriteCloser`) on cgo and purego, with a Go test that the assertion exists.
- `plugins/json`: `type_hook` on value structs and enums emitting `MarshalJSON` /
  `UnmarshalJSON` with a field-name option; used by example 10's `RGB`/`Region`.
- Example READMEs, `docs/examples.md`, `CHANGELOG.md`.

## Done When

- Both plugins have golden cases and example tests on both backends;
  `scripts/release.sh` checks pass.
