---
depends_on:
- "185-ir-target-namespacing#1"
perf_phase: false
status: in-progress
---
> DONE-WHEN: `SemanticFn` declares none of the fields this plan moves outside `go`.
> NEXT: none

# Move the Go standard-library features

## Planned Work

- Move `SemanticFn.iterator` and `SemanticFn.implements` onto `FnGo` as
  `iterator` and `implements`. Both name Go standard-library shapes —
  `iter.Seq` and the four `io` interfaces — so they belong in the namespace even
  though the `implements` and `iterator` built-in plugins own them.
- Repoint the phase 0 accessors and the `implements` and `iterator` plugins in
  `src/gen/plugins/` at the nested fields.
- Update the `iterator` comparison in `src/gen/abi_diff.zig` and confirm it still
  reports an added, removed or renamed iterator wrapper as a contract change.
- Extend the version-1 parse test to cover both fields.
- Make `migrate` key on the old spellings being present rather than on the
  version number, and merge into an existing `go` object rather than replacing
  it. The fields move across two commits, so a document written between them
  claims version 2 while still spelling `iterator` and `implements` at the top
  level, next to a `go` object that already holds `owner`. `abi-check` reads its
  baseline with `git show <ref>:zigo/semantic.json` and so can be handed exactly
  such a document. Cover it with a test.
- Regenerate the generator cases (expecting no diff) and the example outputs,
  and review the diff.

## Done When

- `SemanticFn` declares none of the fields this plan moves outside `go`.
  `cancel`, `cancel_error` and `package` stay where they are: cancellation is
  the one binding concept with no Rust analogue and needs its own design rather
  than a rename, and sub-packages are a general module concept. Both are named
  as non-goals in GOALS.
- The `abi_diff` tests covering iterator changes pass unchanged in behaviour.
- A test asserts that a document mixing the old and new spellings parses with
  both readable, and that a document from an unknown future version keeps its
  own `ir_version` rather than being rewritten.
- `scripts/update-generator-cases.sh` leaves `tests/generator_cases` clean, and
  the only regenerated files under `examples/` are the three `semantic.json`
  outputs that use `.iterator` or `.implements`.
- `zig build test --summary all` passes at the repository root, and
  `zig build test go-check go-lib abi-check go-coverage` followed by
  `go test ./...` passes in every example.
