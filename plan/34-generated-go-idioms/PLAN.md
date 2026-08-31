---
description: "Make generated Go read like hand-written Go: camelCase identifiers, keyword-safe names, sentence GoDoc, canonical formatting without an external gofmt, and a package name override"
plan_status: in-progress
registered_at: "2026-08-31T06:42:53Z"
---
> NEXT: Emit canonical Go so generated files no longer depend on an external gofmt. ([Phase 0](phases/00-canonical-formatting.md))

# Phases

- [x] [Phase 00: Deterministic Formatting](phases/00-canonical-formatting.md)
- [x] [Phase 01: Go Naming for the Public API](phases/01-public-naming.md)
- [ ] [Phase 02: Readable Comments and Diagnostics](phases/02-comments-and-diagnostics.md)
- [ ] [Phase 03: Public Package Name Override](phases/03-package-name-override.md)

# Shared Verification

- Zig: `zig build check` and `zig build test --summary all`, including naming, keyword-escaping and
  formatting unit tests plus the generator cases.
- Formatting: generation with `gofmt` removed from `PATH` produces the committed bytes, and
  `gofmt -l` is empty for every generated directory.
- Go: every example passes `go vet ./...` and `go test ./...` for cgo, and `CGO_ENABLED=0 go test
  ./...` for purego.
- Compatibility: `zigo/semantic.json`, `errors.lock.json` and the generated C header are unchanged
  by this plan, and `abi-check` reports no breaking change for the examples.

# Decisions That Constrain Ordering

Canonical formatting comes first so that every later phase is reviewed as a content diff rather
than a reformatting diff. Naming precedes comments because a comment repeats the identifier it
documents. The package name override comes last because it builds on the validated naming helpers.

# Next Implementation Target

Emit canonical Go so generated files no longer depend on an external gofmt.
