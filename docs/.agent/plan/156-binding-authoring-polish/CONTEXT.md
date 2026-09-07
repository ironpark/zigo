# SCOPE

Public authoring helpers, normalization, shared callback layout, regression tests, examples and docs.

# CONTEXT

## Current implementation and bottlenecks

Examples retain 126 name-only Param literals, repeated scopes, deep contract literals and mixed callback indexing conventions.

## Target structure and invariants

Helpers produce existing structs; with and members replace rather than accumulate. Constructor receivers explicitly distinguish none, member context and a type reference. Callback indices refer to original native arguments; token/length annotations fail. Source-derived public names and ABI must remain stable.
