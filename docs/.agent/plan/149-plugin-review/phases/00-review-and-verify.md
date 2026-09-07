---
completed_at: "2026-09-07T10:38:11Z"
perf_phase: false
status: done
---
> DONE-WHEN: Review evidence and limitations are recorded and findings are ready to deliver to the user.
> NEXT: none

# Review and verify

## Planned Work

- Inspect plugin changes and surrounding call sites; verify suspected defects with focused checks.
- Report findings with file locations and record verification results.

## Done When

- Review evidence and limitations are recorded and findings are ready to deliver to the user.

## Review evidence

Reviewed the committed plugin implementation at bb146612, including declaration transport, registry/build wiring, validation, hooks, imports, built-in migrations and the JSON/SATIS showcases. The initial working tree was clean: there were no existing changes to commit.

- `zig build test -Dtest-filter=plugin`: passed.
- `zig build test`: passed.
- P2, `src/declare.zig:39`: explicit null plugin options are omitted during serialization. A focused Zig test using `Options { limit: ?u32 = 10 }` and `.limit = null` encoded `{}` and decoded `10`. Preserve null values in the plugin payload; missing required nullable fields can also fail parsing.
- P2, `plugins/json/src/plugin.zig:97`: the JSON wire struct uses the bare type node and loses a field's codepoint semantic hint. Adding `semantic: codepoint` to a uint32 field in the JSON golden fixture produced public `rune` and wire `uint32`; Go rejected both struct literals. Reuse the public field spelling, including semantic hints.
- P2, `src/gen/validate/validate.zig:168`: validators run for every registered plugin regardless of the generator's selected plugin subset. The golden runner with `plugins: []` and invalid JSON options still failed with `InvalidSemantic`, although no JSON hook was selected. Apply the same selection to external-plugin validation as to emission.

Reproductions ran in an OS temporary directory using the current generator case runner. Its empty expected directory deliberately yields SnapshotMismatch after successful code generation. The Go reproduction compiled the generated public files with a minimal raw type stub to isolate the field assignment errors from native linking. No implementation fixes were made. Test coverage currently passes despite these reproduced defects.
