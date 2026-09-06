# SCOPE

- `src/reflect/walk.zig`: `.strings`, `.string_release`, callback contract
  defaults.
- `src/reflect/names.zig`: declaration matching and the unqualified fallback.
- `src/reflect/coverage.zig`, `src/main.zig`, `build.zig`,
  `src/build_options.zig`: extra source roots for enrichment.
- `docs/bindings-types.md`, `docs/bindings-functions.md`,
  `docs/bindings-callbacks.md`, `docs/configuration.md`, `docs/cheatsheet.md`,
  `CHANGELOG.md`.
- `tests/generator_cases/`, reflection tests in the touched modules.

Not touched: lowering, emitters, ABI, diagnostics codes other than the ones a
new default can violate.

# CONTEXT

## Current implementation and bottlenecks

`resolveCodepointHint` (`walk.zig:1331`) is the shape every define-level
default should copy: an explicit hint wins, `.integer` opts out and records
nothing, otherwise inference marks the position. Strings have no equivalent, so
each position is written by hand.

`names.zig` matches a source declaration to a reflected function by
`function.name` plus owner (`enrichMatches`, `walk`-recorded `receiver orelse
namespace`). Two things break: the binding's Go-facing `name` is not the
declaration name once `.name` or `strip_prefix` renamed it -- `zig_path` holds
the declaration -- and the unqualified fallback at `names.zig:336`, which
exists for generic factories' anonymous containers, matches on name and arity
alone and so reaches across owners and files.

## Target structure and invariants

- A define-level default never overrides a written hint, and its opt-out
  records nothing, exactly as `.integer` does today.
- A callback contract on a type entry is a default: a `param_meta` at the call
  site overrides field by field.
- Enrichment matches the declaration the binding named. When the binding
  renamed it, `zig_path` is the name to compare. A fallback match may not cross
  an owner that the document states.
