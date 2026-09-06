---
completed_at: "2026-09-06T15:01:40Z"
perf_phase: false
status: done
---
> DONE-WHEN: A wrapper bound from `root.searchFeed` takes its names from that declaration
> NEXT: none

# Correct and widen name enrichment

## Planned Work

- Match on the declaration the binding named: compare the last segment of
  `zig_path` when it is present, and only then `name`.
- Constrain the unqualified fallback so it cannot take a declaration whose
  owner the document contradicts; keep it working for the generic-factory case
  it exists for.
- Reach the bound module's dependency sources so a declaration in another
  module can be matched at all.
- Regression tests: two same-named declarations in different files with
  different parameter names, a `strip_prefix` group, and an explicit `.name`.

## Done When

- A wrapper bound from `root.searchFeed` takes its names from that declaration
  and never from another file's `feed`, and a dependency-module declaration
  contributes its parameter names and doc.
