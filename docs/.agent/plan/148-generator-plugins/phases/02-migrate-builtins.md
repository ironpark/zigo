---
depends_on:
- "148-generator-plugins#1"
perf_phase: false
status: in-progress
---
> DONE-WHEN: `src/gen/plugins/registry.zig` lists four built-ins; `public.zig` has no feature-
> NEXT: none

# Migrate built-ins onto the frame

## Planned Work

- Move `iterators.zig` → `plugins/iterator.zig` (`method_hook`, validator from
  `iteratorIssue`, name-clash rule stays in `names.zig`), then `implements`, then
  `must` (`method_hook` gated by `options.go_must_variants`), then `interfaces`
  (`files` + validator). Each move is one commit with goldens byte-identical.
- The declaration keys stay; the plugins read the typed fields directly (in-tree
  privilege) and document that out-of-tree plugins use `ext`.
- Delete the direct calls from `public.zig` once all four run through hooks.

## Done When

- `src/gen/plugins/registry.zig` lists four built-ins; `public.zig` has no feature-
  specific wrapper calls; every golden and example is unchanged.
