---
description: "Let a purego binding set configure how its shared library is found: candidate paths, environment lookup, automatic first-use loading, and whether the loader API is exported"
plan_status: in-progress
registered_at: "2026-08-31T05:51:27Z"
---
> NEXT: Define the library loading option, validate it, and thread it through the generator. ([Phase 0](phases/00-loading-policy-option.md))

# Phases

- [x] [Phase 00: Loading Policy Option and Plumbing](phases/00-loading-policy-option.md)
- [x] [Phase 01: Candidate Path Resolution](phases/01-candidate-resolution.md)
- [ ] [Phase 02: Automatic Loading and Loader Visibility](phases/02-automatic-and-visibility.md)
- [ ] [Phase 03: Example, Documentation, and CI](phases/03-example-docs-ci.md)

# Shared Verification

- Zig: `zig build check` and `zig build test --summary all`, including validation, CLI, report and
  emitter tests for default, search-path, automatic, and unexported-loader policies.
- Generated output: `zig build go-check` in every example and a clean `git status` after
  regeneration on macOS and Linux.
- Go: `CGO_ENABLED=0 go test ./...` for every purego example, including the configured one, plus a
  concurrent first-use test.
- Failure paths: a missing artifact under an automatic policy reports every attempted candidate.

# Decisions That Constrain Ordering

The option and its validation must exist before any generated code reads it. Candidate resolution
precedes automatic loading, because automatic loading is the candidate list without an explicit
argument. The example, documentation and CI wait until both generation modes work.

# Next Implementation Target

Define the library loading option, validate it, and thread it through the generator.
