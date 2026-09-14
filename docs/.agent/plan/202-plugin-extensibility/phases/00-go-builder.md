---
completed_at: "2026-09-14T06:57:04Z"
perf_phase: false
status: done
---
> DONE-WHEN: `grep -rn "writeAll(\|\.print(" plugins src/gen/plugins` finds no calls that emit Go syntax (comments and diagnostics text excepted).
> NEXT: none

# Go builder layer

## Planned Work

- Add `src/plugin/gobuild.zig`: a small Go AST builder with `File`/`Decl`/`Stmt`/`Expr` nodes covering func, method, var, const, type alias, if/else, switch/case, for range, return, assign, call, selector, index, composite literal, string/int literals, raw expression escape hatch, and doc comments. Deterministic rendering into `*std.Io.Writer`, gofmt-compatible indentation.
- Give the builder access to the existing `Writers` operations (type names, signatures, receiver names, identifiers) so `Expr.typeName(decl)` and `Decl.method(fn)` use the generator's spelling.
- Expose it as `plugin.Builder` on every render context (`Context.builder()`); keep `Context.writeX` helpers only as thin wrappers over builder nodes, then remove the ones no longer used.
- Port `plugins/json`, `plugins/enumkit`, `plugins/satisfies`, and the built-ins `must`, `iterator`, `implements`, `interfaces`, `session` to the builder. No `writer.print`/`writeAll` of Go syntax remains in plugins.
- Unit tests for the builder in `src/plugin/gobuild.zig`; bump `contract_version` to 5.0.

## Done When

- `grep -rn "writeAll(\|\.print(" plugins src/gen/plugins` finds no calls that emit Go syntax (comments and diagnostics text excepted).
- Goldens and example Go trees byte-identical after regeneration; root `zig build test` and each `plugins/<name>` `zig build test` pass.
