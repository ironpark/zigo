# SCOPE

Public authoring API, example bindings and current guides; no IR or ABI changes.

# CONTEXT

Baseline 9df13ca7; existing function bodies can be retained while renaming their declarations.

## Current implementation and bottlenecks

User chose replacement instead of aliases and selected enumType because enum is a Zig keyword.

## Target structure and invariants

Scope exposes func/funcs/val/enumType; Context forwards func/funcs. Internal fields and representations are unchanged.
