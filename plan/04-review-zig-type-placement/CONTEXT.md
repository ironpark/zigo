# SCOPE

Assess canonical implementations, semantic ownership, fixed versus factory form, intended visibility, aliases, physical location, and split-file form. Preserve current source behavior and public API during the audit.

# CONTEXT

## Current implementation and bottlenecks

The top of `src/` contains both `root.zig` and `main.zig`, so automatic public-root selection is ambiguous. `build.zig` is the public build API and also exposes several source files as independent Zig modules, meaning a single root traversal cannot represent every module boundary. No placement policy has yet been found by text search.

## Target structure and invariants

Aliases are never treated as canonical bodies; lexical and semantic ownership remain distinct; ownership, form, visibility, and physical placement are assessed independently; unknown computed aliases stay marked unresolved; recommendations include compatibility and import-cycle analysis.
