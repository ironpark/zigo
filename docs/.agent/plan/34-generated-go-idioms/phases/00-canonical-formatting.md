---
completed_at: "2026-08-31T06:53:41Z"
perf_phase: false
status: done
---

# Deterministic Formatting

## Planned Work

- Measurement changed the approach. Emitting canonical Go by hand would make zigo own a formatting
  contract that `gofmt` changes between Go releases: Go 1.19 reformats doc comments, so
  hand-canonical output would be reported unformatted by a newer `gofmt`. `gofmt` also ships with
  every Go distribution, which zigo already requires. The dependency is therefore kept and the
  silent fallback that makes output environment dependent is removed.
- Fail generation with an actionable message when `gofmt` cannot be found, instead of silently
  committing unformatted output, and let a project point at a specific `gofmt`.
- Make `go-doctor` report a missing `gofmt` as a failure rather than a warning, and update the
  documentation that calls formatting optional.

## Done When

- Generation without `gofmt` fails and names the fix, generation with it is unchanged, doctor
  reports the new requirement, and every example still passes `go-check` with identical files.
