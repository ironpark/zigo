# SCOPE

Modify `.gitignore`, create the ignored `ref/zls` checkout, and record this plan.

# CONTEXT

## Current implementation and bottlenecks

No `ref/` ignore rule or local zls reference checkout currently exists.

## Target structure and invariants

`ref/zls` remains local-only and points at the official upstream 0.16.x line without altering project dependencies.
