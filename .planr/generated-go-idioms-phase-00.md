---
perf_phase: false
planr_base: sha256:69317089011978537fb06af4a39340de5539cd35f1e5bf1c9b8d65c654e56c18
planr_edit: "generated-go-idioms#0"
planr_phase: 0
planr_slug: canonical-formatting
planr_target: plan/34-generated-go-idioms/phases/00-canonical-formatting.md
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
