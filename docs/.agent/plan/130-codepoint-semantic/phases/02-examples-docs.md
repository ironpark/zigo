---
depends_on:
- "130-codepoint-semantic#1"
perf_phase: false
status: in-progress
---
> DONE-WHEN: `zig build go-check` / `purego-go-check` current and `go vet` / `go test` pass on both backends for 02 and 11.
> NEXT: none

# Examples and docs

## Planned Work

- Examples 02 (`codepointWidth`) and 11 (`sumCodepoints`, `fillCodepoints`, `takeCodepoints`) take the hint; regenerate cgo and purego trees and update Go tests to use `rune`.
- Document the hint in `bindings-functions.md` and `bindings-types.md`, add CHANGELOG entry.

## Done When

- `zig build go-check` / `purego-go-check` current and `go vet` / `go test` pass on both backends for 02 and 11.
