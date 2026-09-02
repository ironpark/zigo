# SCOPE

- IR: parameter type `.flattened_struct = .{ .zig_path, .fields = [...] }`, lowered to N scalar C parameters; the shim writes `.{ .cols = cols, .rows = rows, ... }` with unlisted fields omitted so Zig fills defaults.
- `params` naming counts the struct as one entry (its name), flattened Go parameters take `<param>_<field>` only on collision, else the field name.

# CONTEXT

## Current implementation and bottlenecks

- Value structs are rejected by `unsupportedValueStruct` unless `extern` and registered `.repr = .value`.
- Optional scalar parameters: check current support before deciding the Go shape; if unsupported, restrict flatten to non-optional fields in this plan and diagnose.

## Target structure and invariants

- The Zig struct literal in the shim mentions only listed fields, so a new upstream field with a default never breaks the binding, and a new field without a default fails at Zig compile time in the shim (accepted behaviour, documented).
