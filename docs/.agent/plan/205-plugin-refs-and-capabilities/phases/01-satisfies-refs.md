---
depends_on:
- "205-plugin-refs-and-capabilities#0"
perf_phase: false
status: planned
---
> DONE-WHEN: Example 11 `go-verify` and `go test ./...` pass with a generated-interface assertion; a wrong name in a test binding yields `SATIS002`/`SATIS003`.
> NEXT: none

# satisfies with checked interfaces

## Planned Work

- `plugins/satisfies` options become `interfaces: []const Interface` where `Interface = union(enum) { stdlib: []const u8, generated: plugin.ref.Interface }`; JSON form keeps a bare string for stdlib and `{ "generated": "Batch" }` for refs (or a `zigo:` prefix if unions are awkward).
- Stdlib check: a table of Go standard-library interfaces the plugin knows (`fmt.Stringer`, `io.*`, `error`, `encoding.TextMarshaler`, ... a maintained list in the plugin) with their method sets; a name not in the table is diagnostic `SATIS002` with a hint to use a generated interface ref.
- Generated check: resolve the ref, then verify the receiver type implements every method of the generated interface (by name and signature spelled through `Writers`); mismatch is `SATIS003` naming the missing method.
- Example 11 (`satisfies`) adds a `zigo.interface` and a `use(satisfies.plugin, .{ .interfaces = &.{ .{ .generated = Batch } } })` on a handle; regenerate; add a Go compile-time assertion test.
- Update `plugins/satisfies/README.md`, docs, golden, plugin unit tests, CHANGELOG.

## Done When

- Example 11 `go-verify` and `go test ./...` pass with a generated-interface assertion; a wrong name in a test binding yields `SATIS002`/`SATIS003`.
