# SCOPE

- Notes are suggestions only; they never change validation outcomes.
- Contract enums default to unspecified so existing bindings and snapshots stay unchanged unless the metadata is set.

# CONTEXT

## Current implementation and bottlenecks

- `diagnostic.zig` renders severity/code/message/site/hint only.
- Callback `param_meta` supports `retention` only (plus stream direction fields).

## Target structure and invariants

- Snapshot output for existing diagnostics gains only an extra `note:` line where populated.
