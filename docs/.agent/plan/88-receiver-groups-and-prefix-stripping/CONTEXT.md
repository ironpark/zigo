# SCOPE

- Schema: entry fields `receiver`, `strip_prefix`, and `functions` (group). A group may set `params`/`param_meta` per nested entry only, not at group level.
- Naming: strip prefix then lower-case the first character (`screenSelectAll` → `selectAll`), then the usual Go exported casing; conflicts go through ZIGO024.

# CONTEXT

## Current implementation and bottlenecks

- `walk.zig` decides receiver-ness from the declaring container (`receiverIndex`), so a free function on `root` never gets a receiver even when its first parameter is `*Screen`.
- Names come from the Zig declaration or `.name`; there is no group-level rule.

## Target structure and invariants

- A function has at most one receiver, determined by declaration container or explicit `.receiver`; downstream stages cannot tell the two apart.
