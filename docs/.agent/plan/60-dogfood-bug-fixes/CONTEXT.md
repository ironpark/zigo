# SCOPE

Generator (reflect + gen), build.zig publish/prune step, sync_check, affected examples,
goldens, and docs (docs/bindings.md, docs/generated-code.md, docs/limitations.md as
applicable). No changes to committed example APIs except where a fixture is added.

# CONTEXT

## Current implementation and bottlenecks

- Constructor detection is purely name-based (`init/create/new/open`); explicit
  `.returns = .caller` on other names sets ownership but registers no constructor, so
  emit's owned-handle wrapping paths (which look up `program.constructors`) miss it and
  the raw result leaks into typed Go signatures.
- PublishGeneratedGo walks `generated` dir into `published`, then recursively deletes
  any marker-bearing `.go` under `go_dir` not in `published` — including under
  `.zig-cache`. sync_check has the same unfiltered walk (report-only).
- typeNode switches on `@typeInfo` with no `.optional` case; semantic IR already has
  `.optional` and `opaque_ptr.nullable` so the gap is reflection-only, plus emit paths
  must honor nullable for parameter marshalling.
- writeGoDoc prefixes the Go name and lowercases a leading capitalized word, but never
  checks whether the doc's first token IS the declaration's Zig/Go name.

## Target structure and invariants

- Ownership metadata is authoritative: any function with `.returns = .caller` and an
  opaque-pointer payload participates in the same owned-handle construction path as
  named constructors (wrap with `newX`, callback-handle plumbing if applicable).
  Payloads that cannot be wrapped get a new ZIGO diagnostic instead of broken Go.
- Prune/check walks never descend into `.zig-cache` or `zig-out` (skip by directory
  name at any depth).
- `?*T`/`?*const T` opaque parameters map to a nil-able Go handle argument: nil handle
  (or nil pointer) marshals as NULL without a HandleError; non-optional params keep the
  existing checked-pointer error. Both backends and goldens stay in lockstep.
- Doc rule: if the first word of the user doc equals the declaration's original or Go
  name (case-insensitive), drop that word before applying the standard `// GoName ...`
  prefix logic.
