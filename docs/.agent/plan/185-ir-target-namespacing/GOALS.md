# GOALS

## Problem and the end result from the user's point of view

The semantic IR in `src/gen/ir/semantic.zig` is the document every later stage
reads, and it is meant to describe the bound Zig API rather than the language it
is projected into. Eleven of its fields describe Go instead: `Parameter.go_error`,
`Parameter.go_adapter`, `SemanticFn.go_name`, `SemanticFn.go_owner`,
`SemanticFn.return_go_adapter`, `SemanticFn.iterator`, `SemanticFn.implements`,
`TypeDecl.go_adapter`, and the `GoAdapter` and `Implements` types they carry.

They sit as siblings of language-neutral fields, so nothing marks where the
Go projection starts. Research in `docs/.agent/research/rust-target-feasibility.md`
found this is the first thing that blocks a second output language: a Rust
backend would have to reinterpret fields named for Go, and every new Go-only
knob would keep landing in the shared namespace.

Afterwards the document has one place per output language. A reader can tell at
a glance which parts of `semantic.json` describe Zig and which describe Go, and
adding a target means adding a namespace rather than more sibling fields.

## Measurable goals

- Every Go-specific field on `Parameter`, `SemanticFn` and `TypeDecl` is nested
  under one `go` object per declaration, in the Zig types and in `semantic.json`.
- No code outside `src/gen/ir/semantic.zig` and the four writer sites reads a
  Go-specific field by direct member access; readers go through accessors.
- `Semantic.ir_version` is `2`, and a document written at version 1 still parses
  into an identical in-memory `Semantic`.
- `zig build test go-check abi-check go-coverage` stays green, and the generated
  Go output for all 74 generator cases is byte-identical to today.

## Supported scope and non-goals

In scope: the `Parameter`, `SemanticFn` and `TypeDecl` Go fields, their accessors,
the `Semantic.parse` migration, and the regenerated `semantic.json` snapshots.

Non-goals, each deliberately left for a later plan:

- The author-facing DSL in `src/declare.zig`, `src/author.zig` and `src/root.zig`.
  Its `go:` / `go_error` / `go_name` spellings are user-visible; renaming them is
  a separate breaking change with its own migration.
- Extracting a `Target` interface from `src/gen/naming.zig` (Go keywords,
  identifier and package-name rules).
- The plugin contract in `src/plugin.zig`, whose `writeGoType`, `GoFile` and
  `GoPackage` are Go-typed. Only its reads of moved IR fields are updated here.
- `Package` and the `package` fields. Sub-packages are a general module concept,
  not a Go-only one.
- Any Rust emitter.

## Reference source / commit / license

Baseline `8f7d9b6a` on `main`. Prior art inside this repository:
`semantic.Extensions` already keeps per-plugin JSON in a namespace that
round-trips verbatim, and `scripts/migrate-bindings.py` is the precedent for
migrating a document shape.

## Completion criteria for the whole plan

All three phases are `done`, `planr overview` reports the plan complete,
`zig build test go-check abi-check go-coverage --summary all` passes, and
`git status --short tests/generator_cases` is clean after
`scripts/update-generator-cases.sh` runs.
