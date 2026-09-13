---
completed_at: "2026-09-13T18:48:55Z"
perf_phase: false
status: done
---
> DONE-WHEN: `grep -rn "extend(" build.zig plugins src/gen/plugins` returns nothing referring to the DSL.
> NEXT: none

# Docs, comments, dead code

## Planned Work

- Delete `src/dsl.zig` and its `pub const dsl` re-export in `src/root.zig`.
- Delete unreachable legacy builders in `src/declare.zig`: `Function.with/extend/constructor/destructor/childOfReceiver/callerOwned/releasedBy/borrowed`, `Handle/Value/Enum/TaggedUnion.extend` (keep `HandleField.extend` used by `reflect/walk.zig`), `Methods`/`strip_prefix`, and the string `Discover`/`exclude` form if `normalize.zig` can take typed `Discovery` directly.
- Replace `extend(` with `use(` in doc comments: `build.zig:75,79,507,549`, `plugins/json/src/plugin.zig:19`, `plugins/satisfies/src/plugin.zig:18`, `src/gen/plugins/iterator.zig:8`, `src/gen/plugins/testing.zig:16`.
- Fix `docs/plugins/authoring.md` `targets` → `subjects`; reconcile contract version to 3.1 in `docs/plugins/README.md` and `docs/plugins/api-reference.md`.
- Remove the stale `Must*` doc comment on `plugin_config` in `build.zig`.
- Document `addRustBindings`/`RustOptions`/`RustBindings` and `rust*` steps in `docs/reference/build-options.md`.

## Done When

- `grep -rn "extend(" build.zig plugins src/gen/plugins` returns nothing referring to the DSL.
- `zig build test` and `zig build go-verify` in every example pass; example goldens unchanged.
