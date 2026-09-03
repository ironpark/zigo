# GOALS

## Problem and the end result from the user's point of view

Two `go-coverage` (plan 92, `src/reflect/coverage.zig`) defects reported from gostty.

B. Wrappers are not linked to what they cover. A binding project writes `root.zig` wrappers only when an upstream signature cannot cross C (`Terminal.setAttribute`, `Screen.selectAll`, `Search.matchesLen`, `RenderState.update`); the report lists those upstream functions as `unbound` although Go can reach them through the wrapper. gostty counts 19 such cases: reported 140/253 (55%), real 159/253 (63%). End result: a function entry may carry `.covers = "Terminal.setAttribute"` (or a list), the reflector records it, and the report counts the covered declaration as bound with a `wrapped` classification that is listed separately from `unbound` so "deliberately wrapped" and "not exposed" stay distinct.

C. The unregistered types list prints broken or wrong names: `Coordinate),true)` is a truncated `@typeName` of a generic instantiation (same family as the old ZIGO021 truncation), `C__struct_117396` is a translate-c anonymous struct that no binding could register, and `Options` is listed although it is in use through `.flatten` and present in semantic.json as a `value_struct`. End result: names are the full readable `@typeName` when a short name would be ambiguous or malformed (never cut inside parentheses), translate-c anonymous types are filtered out (or grouped under one line), and types that appear in the document (registered, flattened, auto-appended value structs, enums, callbacks) are never reported as unregistered.

## Measurable goals

- `.covers` on a function entry: string or list of `<Type>.<name>` / `root.<name>` paths that must resolve to public declarations reachable by the coverage walk, else a compile error naming the path (same style as unknown `.path`). Recorded in semantic.json on the function (`covers: [...]`) so `abi-diff` treats it as documentation only (no change class).
- Report: covered declarations count as bound; a new `wrapped:` section lists `<upstream> <- <wrapper>`; summary line becomes `bound/total (pct)` with bound including wrapped; JSON output gains `wrapped` entries with `via`.
- Unregistered list: `walk.shortTypeName` is not used on names containing `(`; a name is shown as the full `@typeName` minus the root module prefix when it contains `(`; translate-c names (`C__struct_`, `cimport.`) are excluded; any type whose `@typeName` matches a document `TypeDecl.zig_path` (including `#`-disambiguated registrations and auto-appended value structs) is excluded. Unit tests for each rule in `coverage.zig` (build documents through real reflection, no `undefined`).
- docs `configuration.md` `go-coverage` section and `bindings.md` function metadata table; CHANGELOG `## [Unreleased]` `### Added` (covers) and `### Fixed` (names).
- No generated Go/C/shim output changes; verification loop green.

## Supported scope and non-goals

In scope: `src/reflect/walk.zig` (metadata schema for `.covers`, validation of the paths), `src/reflect/coverage.zig`, `src/gen/ir/semantic.zig` (`covers` field), `src/gen/abi_diff.zig` (ignore `covers`), docs, tests, at least one example using `.covers` (extend 01, which already has the deliberately unbound `subtract`, or 07).
Non-goals: inferring coverage automatically from wrapper bodies; changing how `unbound` reasons are derived.

## Reference source / commit / license

Current main; plan 92 (coverage report); `walk.zig` `shortTypeName`; the ZIGO021 emitted-name history for the truncation family.

## Completion criteria for the whole plan

Both phases done; verification loop green; tree clean.
