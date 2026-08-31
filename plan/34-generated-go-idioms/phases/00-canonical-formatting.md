---
perf_phase: false
status: in-progress
---
> DONE-WHEN: Generation with no `gofmt` on `PATH` reproduces the committed files byte for byte, `gofmt -l`
> NEXT: none

# Canonical Formatting Without gofmt

## Planned Work

- Emit already-canonical Go: expanded statements and blocks, and `gofmt` alignment for struct
  fields, const and var blocks.
- Remove the `gofmt` pass from the build graph along with the options and diagnostics that exist
  only to feed it, keeping the committed files unchanged.
- Add a check that every generated file equals its `gofmt` output, so a formatting regression fails
  the build instead of being repaired silently.

## Done When

- Generation with no `gofmt` on `PATH` reproduces the committed files byte for byte, `gofmt -l`
  reports nothing for every generated directory, and every example still passes `go-check`.
