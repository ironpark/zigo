---
depends_on:
- "50-idiomatic-go-bindings#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Regenerated examples show one `const` block per enum; every handle type
> NEXT: none

# Idiomatic small surface: enum blocks, Close() error, helper cleanup

## Planned Work

- Emit each enum as a single `const ( ... )` block with one leading doc
  comment; switch `String()` fallbacks to `strconv.Itoa(int(v))` (or
  `FormatUint` where unsigned width demands it).
- Change generated `Close()` to `Close() error` returning nil, satisfying
  `io.Closer`; update docs and example tests.
- Sweep small helper output (`boolToUint8` and friends) for gofmt/vet
  cleanliness under the new emission.

## Done When

- Regenerated examples show one `const` block per enum; every handle type
  asserts against `io.Closer` in at least one example test.
- `gofmt -l` and `go vet` are clean on all regenerated trees; `zig build test`
  passes.
