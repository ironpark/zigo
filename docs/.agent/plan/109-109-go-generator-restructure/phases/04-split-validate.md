---
completed_at: "2026-09-05T07:21:15Z"
depends_on:
- "109-109-go-generator-restructure#1"
perf_phase: false
status: done
---
> DONE-WHEN: No file under `src/gen/validate/` exceeds 1,500 lines.
> NEXT: none

# Split validate.zig into an ordered rule list

## Planned Work

- Create `src/gen/validate/` with `validate.zig` (public API and the ordered
  rule list), `packages.zig`, `names.zig`, `types.zig`, `callbacks.zig`,
  `ownership.zig`, `materialized.zig`, `site.zig` (diagnostic construction).
- `findIssue` becomes a loop over `rules: []const Rule` where each rule is
  `fn (Allocator, Semantic) !?Diagnostic`, listed in today's loop order.
- Move functions verbatim; keep tests beside their rules.

## Done When

- No file under `src/gen/validate/` exceeds 1,500 lines.
- Every diagnostic test and generator case passes unchanged.
